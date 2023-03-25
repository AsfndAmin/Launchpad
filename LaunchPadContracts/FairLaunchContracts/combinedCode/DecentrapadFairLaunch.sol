// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./IDecentrapadFairLaunch.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "./ILock.sol";

contract DecentrapadFairLaunch is
    Ownable,
    ReentrancyGuard,
    IDecentrapadFairLaunch
{
    using SafeERC20 for ERC20;
    using SafeMath for uint256;

    ILock public lockLP;

    struct launchSaleInfo {
        address tokenAddress;
        address paymentToken;
        IUniswapV2Router02 router;
        uint256 tokensForSale;
        uint256 softCap;
        uint256 startTime;
        uint256 endTime;
        uint256 referReward;
        uint256 maxContribution;
    }

    struct dexListingInfo {
        uint256 lpTokensRatio;
        uint256 liquidityLockTime;
    }

    struct launchPoolData {
        uint256 totalRaised;
        uint256 totalTokensClaimed;
        PoolStatus status;
    }

    struct poolFee {
        uint256 nativeFee;
        uint256 tokenFee;
    }

    launchPoolData public poolData;
    dexListingInfo public dexInfo;
    launchSaleInfo public launchInfo;
    poolFee public poolFees;

    mapping(address => uint256) public UserInvestments;
    mapping(address => uint256) public referComission;

    address public platformAddress;
    address public lockAddress;
    uint256 public totalReferReward;
    uint256 constant base = 1000;
    uint256 totalRefferal;
    uint256 referReward;

    bool public feesInNative;
    bool public referRewardStatus;
    bool public maxContributionEnabled;

    constructor(
        launchSaleInfo memory _launchInfo,
        dexListingInfo memory _listingInfo,
        poolFee memory _poolFees,
        address owner,
        address _platform,
        address _lockAddress,
        bool _maxContribution,
        bool _referRewardStatus
    ) {
        transferOwnership(owner);
        launchInfo = _launchInfo;
        dexInfo = _listingInfo;
        poolFees = _poolFees;
        poolData.status = PoolStatus.ACTIVE;
        maxContributionEnabled = _maxContribution;
        platformAddress = _platform;
        referRewardStatus = _referRewardStatus;
        lockLP = ILock(_lockAddress);
    }

    function updateEndTime(uint64 newendTime) public onlyOwner {
        require(poolData.status == PoolStatus.ACTIVE, "NOT ACTIVE");
        require(
            newendTime >= block.timestamp && newendTime < launchInfo.endTime,
            "Sale end can't be less than sale start"
        );
        launchInfo.endTime = newendTime;
    }

    function buyTokens(
        address referAddress,
        uint256 paymentAmount
    ) external payable nonReentrant {
        require(
            block.timestamp >= launchInfo.startTime,
            "Sale not started yet"
        );
        require(block.timestamp < launchInfo.endTime, "Sale Ended");
        require(poolData.status == PoolStatus.ACTIVE, "Pool not active");
        if (maxContributionEnabled) {
            require(
                (UserInvestments[msg.sender] + paymentAmount) <=
                    launchInfo.maxContribution,
                "max Contribution check"
            );
        }

        transferFromHelper(
            launchInfo.paymentToken,
            msg.sender,
            address(this),
            paymentAmount
        );

        UserInvestments[msg.sender] += paymentAmount;

        poolData.totalRaised = poolData.totalRaised.add(paymentAmount);

        if (referRewardStatus) {
            require(msg.sender != referAddress, "Cannot refer itself");
            if (referAddress != address(0)) {
                referComission[referAddress] += paymentAmount;
                totalRefferal += paymentAmount;
            }
        }
        emit TokensBought(msg.sender, referAddress, paymentAmount);
    }

    function calculateShare(
        uint256 _userContributions
    ) private view returns (uint256) {
        require(_userContributions >= 100, "too less contribution");
        uint256 _totalAmountRaised = poolData.totalRaised;
        uint256 _tokensForSale = launchInfo.tokensForSale;
        uint256 _paymentDecimals;

        if (launchInfo.paymentToken != address(0)) {
            _paymentDecimals =
                10 ** (ERC20(launchInfo.paymentToken).decimals());
        } else {
            _paymentDecimals = 10 ** 18;
        }
        uint256 _share = ((_tokensForSale).mul(_paymentDecimals)).div(
            _totalAmountRaised
        );
        uint256 usersShare = ((_userContributions).mul(_share)).div(
            _paymentDecimals
        );
        return usersShare;
    }

    function userClaim() external nonReentrant {
        uint256 userContribution = UserInvestments[msg.sender];
        require(userContribution > 0, "zero contribution");
        uint256 userShare = calculateShare(userContribution);
        uint256 claimedAmount;
        if (poolData.status == PoolStatus.ACTIVE) {
            require(
                !referRewardStatus,
                "Cannot claim early due to refer rewards"
            );
            if (poolData.totalRaised < launchInfo.softCap) {
                uint256 earlyClaimPenalty = userContribution.mul(100).div(10);
                uint256 remainingContribution = userContribution.sub(
                    earlyClaimPenalty
                );

                UserInvestments[msg.sender] = 0;
                poolData.totalRaised -= userContribution;

                transferHelper(
                    launchInfo.paymentToken,
                    platformAddress,
                    earlyClaimPenalty
                );

                transferHelper(
                    launchInfo.paymentToken,
                    msg.sender,
                    remainingContribution
                );
                claimedAmount = remainingContribution;
            } else {
                revert("Cannot claim");
            }
        } else if (poolData.status == PoolStatus.COMPLETED) {
            UserInvestments[msg.sender] = 0;

            transferHelper(launchInfo.tokenAddress, msg.sender, userShare);

            poolData.totalTokensClaimed += userShare;
            claimedAmount = userShare;
        } else if (poolData.status == PoolStatus.CANCELED) {
            UserInvestments[msg.sender] = 0;
            poolData.totalRaised -= userContribution;

            transferHelper(
                launchInfo.paymentToken,
                msg.sender,
                userContribution
            );

            claimedAmount = userContribution;
        }

        emit tokensClaimed(msg.sender, claimedAmount, poolData.status);
    }

    function claimReferReward() external nonReentrant {
        require(referRewardStatus, "Refer reward not exists");
        require(
            poolData.status == PoolStatus.COMPLETED,
            "pool didn't completed yet"
        );

        uint256 userReward = referComissionAmount(msg.sender);
        require(userReward > 0, "zero reward");
        referComission[msg.sender] = 0;

        transferHelper(launchInfo.paymentToken, msg.sender, userReward);

        emit ReferRewardsClaimed(msg.sender, userReward);
    }

    function referComissionAmount(address user) public view returns (uint256) {
        uint256 _paymentDecimals;
        if (launchInfo.paymentToken != address(0)) {
            _paymentDecimals =
                10 ** (ERC20(launchInfo.paymentToken).decimals());
        } else {
            _paymentDecimals = 10 ** 18;
        }
        uint256 _share = ((referReward).mul(_paymentDecimals)).div(
            totalRefferal
        );

        uint256 totalContribution = referComission[user];
        uint256 usersShare = ((totalContribution).mul(_share)).div(
            _paymentDecimals
        );

        return usersShare;
    }

    function enableAffilateReward(uint256 _ratio) external onlyOwner {
        require(poolData.status == PoolStatus.ACTIVE, "not active");
        require(
            _ratio > launchInfo.referReward && _ratio <= 100,
            "ratio error"
        );
        require(launchInfo.endTime > block.timestamp, "ended");
        referRewardStatus = true;
        launchInfo.referReward = _ratio;
        emit affiliateEnabled(_ratio);
    }

    function finalizeLaunch() external onlyOwner {
        require(block.timestamp >= launchInfo.endTime, "Sale not ended");
        require(poolData.status == PoolStatus.ACTIVE, "Already finalized");
        require(
            poolData.totalRaised > launchInfo.softCap,
            "not exceed softcap"
        );

        poolData.status = PoolStatus.COMPLETED;
        uint256 totalAmountRaised = poolData.totalRaised;
        (
            uint256 platformNativeShare,
            uint256 platformTokenShare
        ) = calculatePlatformShare(totalAmountRaised);
        transferHelper(
            launchInfo.paymentToken,
            platformAddress,
            platformNativeShare
        );

        if (platformTokenShare != 0) {
            transferHelper(
                launchInfo.tokenAddress,
                platformAddress,
                platformTokenShare
            );
        }

        uint256 raisedAfterPlatformFee = totalAmountRaised.sub(
            platformNativeShare
        );

        if (referRewardStatus && totalRefferal > 0) {
            referReward = raisedAfterPlatformFee
                .mul(launchInfo.referReward)
                .div(base);
        }

        uint256 amountAfterAffiliate = raisedAfterPlatformFee.sub(referReward);

        uint256 token0Amount = calculateliquidityAmount();
        uint256 token1Amount = calculateLPShare(amountAfterAffiliate);
        require(
            amountAfterAffiliate > token1Amount,
            "amount greater than raised"
        );
        _checkPairCreated();

        if (launchInfo.paymentToken != address(0)) {
            addLiquidity(token0Amount, token1Amount);
        } else {
            addNativeLiquidity(token0Amount, token1Amount);
        }

        uint256 raisedAfterLPAndFees = amountAfterAffiliate.sub(token1Amount);
        transferHelper(
            launchInfo.paymentToken,
            msg.sender,
            raisedAfterLPAndFees
        );

        lockLPTokens();
        emit poolFinalized(totalAmountRaised);
    }

    function lockLPTokens() public {
        address saleToken;
        if (launchInfo.paymentToken == address(0)) {
            saleToken = launchInfo.router.WETH();
        } else {
            saleToken = launchInfo.paymentToken;
        }
        address paymentToken = launchInfo.tokenAddress;
        address factory = launchInfo.router.factory();

        address pairAddress = IUniswapV2Factory(factory).getPair(
            saleToken,
            paymentToken
        );
        uint256 balance = ERC20(pairAddress).balanceOf(address(this));
        require(balance > 0, "Insufficient LP balance");
        ERC20(pairAddress).approve(address(lockLP), balance);
        lockLP.lock(
            owner(),
            pairAddress,
            true,
            balance,
            block.timestamp + dexInfo.liquidityLockTime,
            ""
        );
    }

    function calculateLPShare(
        uint256 _amountRaised
    ) private view returns (uint256) {
        uint256 token1RequiredForLP = _amountRaised
            .mul(dexInfo.lpTokensRatio)
            .div(base);
        return token1RequiredForLP;
    }

    function _checkPairCreated() private returns (bool) {
        address token0;
        if (launchInfo.paymentToken == address(0)) {
            token0 = launchInfo.router.WETH();
        } else {
            token0 = launchInfo.paymentToken;
        }
        address token1 = launchInfo.tokenAddress;
        address factory = launchInfo.router.factory();

        if (IUniswapV2Factory(factory).getPair(token0, token1) == address(0)) {
            IUniswapV2Factory(factory).createPair(token0, token1);
        }
        return true;
    }

    function calculatePlatformShare(
        uint256 _amountRaised
    ) private view returns (uint256, uint256) {
        uint256 platformNativeShare = _amountRaised.mul(poolFees.nativeFee).div(
            base
        );
        uint256 platformTokenShare = launchInfo
            .tokensForSale
            .mul(poolFees.tokenFee)
            .div(base);
        return (platformNativeShare, platformTokenShare);
    }

    function calculateLpTokens() private view returns (uint256) {
        return launchInfo.tokensForSale.mul(dexInfo.lpTokensRatio).div(base);
    }

    function calculateliquidityAmount() private view returns (uint256) {
        uint256 amount;
        uint256 lpAmount = calculateLpTokens();
        if (poolFees.tokenFee > 0) {
            uint256 tokenFee = lpAmount.mul(poolFees.tokenFee).div(base);
            amount = lpAmount.sub(tokenFee);
        } else {
            uint256 tokenFee = lpAmount.mul(poolFees.nativeFee).div(base);
            amount = lpAmount.sub(tokenFee);
        }
        return amount;
    }

    function cancelPool() external onlyOwner {
        require(
            poolData.status == PoolStatus.ACTIVE,
            "Already finalized or cancelled"
        );

        poolData.status = PoolStatus.CANCELED;
        uint256 tokensForSale = IERC20(launchInfo.tokenAddress).balanceOf(
            address(this)
        );
        IERC20(launchInfo.tokenAddress).transfer(msg.sender, tokensForSale);
        renounceOwnership();
        emit poolCancelled(msg.sender);
    }

    function addNativeLiquidity(
        uint256 tokenAmount,
        uint256 ethAmount
    ) private {
        // approve token transfer to cover all possible scenarios
        ERC20(launchInfo.tokenAddress).approve(
            address(launchInfo.router),
            tokenAmount
        );

        // add the liquidity
        launchInfo.router.addLiquidityETH{value: ethAmount}(
            launchInfo.tokenAddress,
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 token0Amount, uint256 token1Amount) private {
        // approve token transfer to cover all possible scenarios
        ERC20(launchInfo.tokenAddress).approve(
            address(launchInfo.router),
            token0Amount
        );
        ERC20(launchInfo.paymentToken).approve(
            address(launchInfo.router),
            token1Amount
        );

        // add the liquidity
        launchInfo.router.addLiquidity(
            launchInfo.tokenAddress,
            launchInfo.paymentToken,
            token0Amount,
            token1Amount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this),
            block.timestamp
        );
    }

    function transferFromHelper(
        address token,
        address from,
        address to,
        uint256 amount
    ) private {
        if (token != address(0)) {
            ERC20(token).safeTransferFrom(from, to, amount);
        } else {
            require(msg.value == amount, "Insufficient ETH sent");
        }
    }

    function transferHelper(address token, address to, uint256 amount) private {
        if (token != address(0)) {
            ERC20(token).safeTransfer(to, amount);
        } else {
            payable(to).transfer(amount);
        }
    }
}
