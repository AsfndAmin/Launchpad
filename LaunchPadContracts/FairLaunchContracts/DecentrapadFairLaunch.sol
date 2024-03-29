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

contract DecentrapadFairLaunch is
    Ownable,
    ReentrancyGuard,
    IDecentrapadFairLaunch
{
    using SafeERC20 for ERC20;
    using SafeMath for uint256;

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
    uint256 public totalReferReward;
    uint256 constant base = 1000;
    bool public feesInNative;
    bool public referRewardStatus;
    bool public maxContributionEnabled;

    constructor(
        launchSaleInfo memory _launchInfo,
        dexListingInfo memory _listingInfo,
        poolFee memory _poolFees,
        address owner,
        bool _maxContribution,
        address _platform
    ) {
        require(
            _launchInfo.referReward > 0 && _launchInfo.referReward <= 100,
            "Invalid reward set"
        );
        transferOwnership(owner);
        launchInfo = _launchInfo;
        dexInfo = _listingInfo;
        poolFees = _poolFees;
        poolData.status = PoolStatus.ACTIVE;
        maxContributionEnabled = _maxContribution;
        platformAddress = _platform;
    }

    function updatesoftCap(uint256 _softCap) public onlyOwner {
        require(_softCap > 0, "Zero cap");
        launchInfo.softCap = _softCap;
    }

    function updateStartTime(uint64 newstartTime) public onlyOwner {
        require(
            block.timestamp < launchInfo.startTime &&
                newstartTime < launchInfo.endTime,
            "Invalid start time"
        );
        launchInfo.startTime = newstartTime;
    }

    function updateEndTime(uint64 newendTime) public onlyOwner {
        require(
            newendTime > launchInfo.startTime && newendTime > block.timestamp,
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

        if (referAddress != address(0)) {
            require(msg.sender != referAddress, "Cannot refer itself");
            uint256 tokenFee = paymentAmount.mul(poolFees.nativeFee).div(base);
            uint256 amount = paymentAmount.sub(tokenFee);
            uint256 userComission = amount.mul(launchInfo.referReward).div(
                base
            );
            referComission[referAddress] += userComission;
            totalReferReward += userComission;
        }
        emit TokensBought(msg.sender, paymentAmount);
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
        require(
            poolData.status == PoolStatus.CANCELED ||
                poolData.status == PoolStatus.COMPLETED,
            "Pool Active"
        );
        uint256 userContribution = UserInvestments[msg.sender];
        require(userContribution > 0, "zero contribution");
        uint256 userShare = calculateShare(userContribution);
        uint256 claimedAmount;

        if (poolData.status == PoolStatus.COMPLETED) {
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
        } else {}

        emit tokensClaimed(msg.sender, claimedAmount, poolData.status);
    }

    function claimReferReward() external nonReentrant {
        require(poolData.status == PoolStatus.COMPLETED, "not finalized");
        uint256 userReward = referComissionAmount(msg.sender);
        require(userReward > 0, "zero reward");
        referComission[msg.sender] = 0;
        transferHelper(launchInfo.paymentToken, msg.sender, userReward);
        emit ReferRewardsClaimed(msg.sender, userReward);
    }

    function referComissionAmount(address user) private view returns (uint256) {
        if (poolData.status == PoolStatus.CANCELED) {
            return 0;
        } else {
            return referComission[user];
        }
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
        uint256 affiliateShare = (
            raisedAfterPlatformFee.mul(launchInfo.referReward)
        ).div(base);
        uint256 amountAfterAffiliate = raisedAfterPlatformFee.sub(
            affiliateShare
        );

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

        dexInfo.liquidityLockTime += block.timestamp;

        uint256 raisedAfterLPAndFees = amountAfterAffiliate.sub(token1Amount);
        transferHelper(
            launchInfo.paymentToken,
            msg.sender,
            raisedAfterLPAndFees
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

    function claimLP() external onlyOwner {
        require(poolData.status == PoolStatus.COMPLETED, "Pool not completed");
        require(dexInfo.liquidityLockTime < block.timestamp, "LP locked");

        address token0;
        if (launchInfo.paymentToken == address(0)) {
            token0 = launchInfo.router.WETH();
        } else {
            token0 = launchInfo.paymentToken;
        }
        address token1 = launchInfo.tokenAddress;
        address factory = launchInfo.router.factory();
        address pairAddress = IUniswapV2Factory(factory).getPair(
            token0,
            token1
        );

        uint256 balance = ERC20(pairAddress).balanceOf(address(this));
        require(balance > 0, "Insufficient LP balance");

        ERC20(pairAddress).safeTransfer(msg.sender, balance);
    }
}
