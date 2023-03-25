// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import "./IDecentrapadFairLaunchWithoutAffiliate.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

contract DecentrapadFairLaunchWithoutAffiliate is
    Ownable,
    ReentrancyGuard,
    IDecentrapadFairLaunchWithoutAffiliate
{
    using SafeERC20 for ERC20;
    using SafeMath for uint256;

    uint256 base = 1000;

    struct launchSaleInfo {
        address tokenAddress;
        address paymentToken;
        IUniswapV2Router02 router;
        uint256 tokensForSale;
        uint256 softCap;
        uint256 startTime;
        uint256 endTime;
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

    address public platformAddress;
    bool public feesInNative;
    bool public maxContributionEnabled;

    mapping(address => uint256) public UserInvestments;

    constructor(
        launchSaleInfo memory _launchInfo,
        dexListingInfo memory _listingInfo,
        poolFee memory _poolFees,
        address owner,
        bool _maxContribution,
        address _platform
    ) {
        transferOwnership(owner);
        launchInfo = _launchInfo;
        dexInfo = _listingInfo;
        poolFees = _poolFees;
        poolData.status = PoolStatus.ACTIVE;
        maxContributionEnabled = _maxContribution;
        platformAddress = _platform;
    }

    function updatesoftCap(uint256 _softCap) public onlyOwner {
        require(_softCap > 0, "Zero max cap");
        launchInfo.softCap = _softCap;
    }

    function updateStartTime(uint64 newstartTime) public onlyOwner {
        require(block.timestamp < launchInfo.startTime, "Sale already started");
        launchInfo.startTime = newstartTime;
    }

    function updateEndTime(uint64 newendTime) public onlyOwner {
        require(
            newendTime > launchInfo.startTime && newendTime > block.timestamp,
            "Sale end can't be less than sale start"
        );
        launchInfo.endTime = newendTime;
    }

    function buyTokens(uint256 paymentAmount) external payable nonReentrant {
        require(block.timestamp > launchInfo.startTime, "Sale not started yet");
        require(block.timestamp < launchInfo.endTime, "Sale Ended");
        require(poolData.status != PoolStatus.CANCELED, "Pool not active");

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
        uint256 usersShare = (_userContributions.mul(_share)).div(
            _paymentDecimals
        );
        return usersShare;
    }

    function userClaim() external nonReentrant {
        uint256 userContribution = UserInvestments[msg.sender];
        require(userContribution > 0, "zero contribution");
        uint256 userShare = calculateShare(userContribution);

        uint256 claimedAmount;

        if (poolData.status == PoolStatus.COMPLETED) {
            UserInvestments[msg.sender] = 0;

            transferHelper(launchInfo.tokenAddress, msg.sender, userShare);

            poolData.totalTokensClaimed += userShare;
            claimedAmount = userShare;
        } else if (poolData.status == PoolStatus.ACTIVE) {
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

    function finalizeLaunch() external onlyOwner {
        require(block.timestamp >= launchInfo.endTime, "Sale not ended");
        require(poolData.status != PoolStatus.COMPLETED, "Already finalized");
        require(poolData.status != PoolStatus.CANCELED, "Already cancel");
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

        uint256 token0Amount = calculateliquidityAmount();
        uint256 token1Amount = calculateLPShare(raisedAfterPlatformFee);
        _checkPairCreated();

        if (launchInfo.paymentToken != address(0)) {
            addLiquidity(token0Amount, token1Amount);
        } else {
            addNativeLiquidity(token0Amount, token1Amount);
        }
        dexInfo.liquidityLockTime += block.timestamp;

        require(
            raisedAfterReferRewards >= paymentTokenAmount,
            "amount greater than raised"
        );
        uint256 raisedAfterLPAndFees = raisedAfterPlatformFee.sub(token1Amount);

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
        if (poolFees.tokenFee > 0) {
            uint256 lpAmount = calculateLpTokens();
            uint256 tokenFee = lpAmount.mul(poolFees.tokenFee).div(base);
            amount = lpAmount.sub(tokenFee);
        } else {
            uint256 lpAmount = calculateLpTokens();
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
