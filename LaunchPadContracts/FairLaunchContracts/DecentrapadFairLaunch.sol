// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";


contract DecentrapadFairLaunch is Ownable, Pausable {
 using SafeERC20 for ERC20;
 using SafeMath for uint256; 

 bool public listingOnDex;

    event UserInvestment(
        address indexed user,
        uint256 amount
    );

    event TokensBought(address user, uint256 amount);
    event tokensClaimed(address user, uint256 amount, PoolStatus);
    event poolCancelled(address user);

    enum PoolStatus {
        ACTIVE,
        CANCELED,
        COMPLETED
    }

    struct launchSaleInfo {
        address tokenAddress;
        address paymentToken;
        IUniswapV2Router02 router;
        uint256 tokensForSale;
        uint256 softCap;
        uint256 startTime;
        uint256 endTime;
        uint256 minBuyLimit;
        uint256 maxBuyLimit;
    }
    launchSaleInfo public launchInfo;

    struct dexListingInfo {
        uint256 maxTokensForLiquidity;
        uint256 lpTokensRatio;
        uint256 liquidityLockTime;
        bool dexListing;

    }
    dexListingInfo public dexInfo;

    struct launchPoolData {
        uint256 totalRaised;
        uint256 totalTokensClaimed;
        PoolStatus status;
    }
    launchPoolData public poolData;
    address public platformAddress = 0x83278c3DCd78d5270f9726684f76962F3ce18ad0;
    uint256 public platformFee;
    mapping(address => uint256) public UserInvestments;

    constructor(
        launchSaleInfo memory _launchInfo,
        dexListingInfo memory _listingInfo,
        address owner,
        bool _listingOnDex
    ) {
        transferOwnership(owner);
        launchInfo = _launchInfo;
        dexInfo = _listingInfo;
        listingOnDex = _listingOnDex;
        platformFee = 50; // 5%
        poolData.status = PoolStatus.ACTIVE;
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

    function buyTokens(uint256 paymentAmount)
        external
        whenNotPaused
        payable
    {
        require(block.timestamp > launchInfo.startTime, "Sale not started yet");
        require(block.timestamp < launchInfo.endTime, "Sale Ended");
        require(paymentAmount >= launchInfo.minBuyLimit && paymentAmount <= launchInfo.maxBuyLimit,"Invalid Amount sent");
        require(poolData.status != PoolStatus.CANCELED, "Pool not active");
        
        if(launchInfo.paymentToken != address(0)) {
            ERC20(launchInfo.paymentToken).safeTransferFrom(msg.sender, address(this), paymentAmount);
        } else {
            require(msg.value == paymentAmount, "ether check");
        }
        UserInvestments[msg.sender] += paymentAmount;

        poolData.totalRaised = poolData.totalRaised.add(paymentAmount);

        emit TokensBought(msg.sender, paymentAmount);
    } 
    function calculateShare(uint256 _userContributions) public view returns(uint256){
        uint256 _totalAmountRaised = poolData.totalRaised;
        uint256 _tokensForSale = launchInfo.tokensForSale;
        uint256 _tokenDecimals = 10**(ERC20(launchInfo.tokenAddress).decimals()); 
        uint256 _paymentDecimals;
        if(launchInfo.paymentToken != address(0)) {
          _paymentDecimals = 10**(ERC20(launchInfo.paymentToken).decimals());
        } else {
          _paymentDecimals = 10**18;
        }
        uint256 share = ((_tokensForSale * _tokenDecimals) * _paymentDecimals)/(_totalAmountRaised * _paymentDecimals);
        uint256 usersShare = (_userContributions * share)/_paymentDecimals;
        return usersShare;
    }


    function userClaim() external {
        uint256 userContribution = UserInvestments[msg.sender];
        require(userContribution > 0, "zero contribution");
        uint256 userShare = calculateShare(userContribution); 
        
        uint256 claimedAmount;

        if(poolData.status == PoolStatus.ACTIVE) {
            if(poolData.totalRaised < launchInfo.softCap) {
                uint256 earlyClaimPenalty = userContribution.mul(100).div(10);
                uint256 remainingContribution = userContribution.sub(earlyClaimPenalty);

                UserInvestments[msg.sender] = 0;
                poolData.totalRaised -= userContribution;

                if(launchInfo.paymentToken != address(0)) {
                    ERC20(launchInfo.paymentToken).safeTransfer(platformAddress, earlyClaimPenalty);
                    ERC20(launchInfo.paymentToken).safeTransfer(msg.sender, remainingContribution);
                } else {
                    payable(platformAddress).transfer(earlyClaimPenalty);
                    payable(msg.sender).transfer(remainingContribution);
                }
                claimedAmount = remainingContribution;
            }
            if(poolData.totalRaised > launchInfo.softCap) {
                revert("Cannot claim");
            }
        }

        if(poolData.status == PoolStatus.CANCELED) {
            UserInvestments[msg.sender] = 0;
            poolData.totalRaised -= userContribution;

            if(launchInfo.paymentToken != address(0)) {
                    ERC20(launchInfo.paymentToken).safeTransfer(msg.sender, userContribution);
                } else {
                    payable(msg.sender).transfer(userContribution);
                }
                claimedAmount = userContribution;
            }

        if(poolData.status == PoolStatus.COMPLETED) {
            UserInvestments[msg.sender] = 0;

            ERC20(launchInfo.tokenAddress).safeTransfer(msg.sender, userShare);
            poolData.totalTokensClaimed += userShare;
           claimedAmount = userShare;
        }

        emit tokensClaimed(msg.sender, claimedAmount, poolData.status);

    }

    function finalizeLaunch() external onlyOwner {
        require(block.timestamp >= launchInfo.endTime, "Sale not ended");//working
        require(poolData.status != PoolStatus.COMPLETED, "Already finalized");//working
        require(poolData.status != PoolStatus.CANCELED, "Already cancel");//working
        require(poolData.totalRaised > launchInfo.softCap, "not exceed softcap");//working

        poolData.status = PoolStatus.COMPLETED;
        uint256 totalAmountRaised = poolData.totalRaised;
        uint256 platformShare = calculatePlatformShare(totalAmountRaised);
                // cut platform fees    
        if(launchInfo.paymentToken != address(0)) {
            ERC20(launchInfo.paymentToken).safeTransfer(platformAddress, platformShare);
        } else {
                payable(platformAddress).transfer(platformShare);
            } 

        uint256 raisedAfterPlatformFee = totalAmountRaised.sub(platformShare);
        (uint256 token0Amount, uint256 token1Amount) = calculateLPShare(raisedAfterPlatformFee);

        // handle LP
        if(listingOnDex) {
            _checkPairCreated();
            if(launchInfo.paymentToken != address(0)) {
                addLiquidity(token0Amount, token1Amount);
            } else {
                addNativeLiquidity(token0Amount, token1Amount);
            }
       
            // return the remaining tokens to owner if any
        dexInfo.liquidityLockTime += block.timestamp;
        }

      require(raisedAfterPlatformFee > token1Amount, "amount greater than raised");
       uint256 raisedAfterLPAndFee = raisedAfterPlatformFee.sub(token1Amount);

       // send remaining BNB/ERC tokens back to owner
        if(launchInfo.paymentToken != address(0)) {
            ERC20(launchInfo.paymentToken).safeTransfer(msg.sender, raisedAfterLPAndFee);
        } else {
            payable(msg.sender).transfer(raisedAfterLPAndFee);
            } 

    }

    function calculateLPShare(uint256 _amountRaised) public view returns(uint256, uint256) {
        uint256 tokens0RequiredForLP = (launchInfo.tokensForSale).mul(1000).div(dexInfo.lpTokensRatio);
        uint256 token1RequiredForLP = _amountRaised.mul(1000).div(dexInfo.lpTokensRatio);
                return (tokens0RequiredForLP, token1RequiredForLP);

    }


    //if payment token is bnb(address 0) then it will take our native token
    function _checkPairCreated() public returns(bool) {
        address token0;
        if(launchInfo.paymentToken == address(0)){
            token0 = launchInfo.router.WETH(); 
        }else{
            token0 = launchInfo.paymentToken;
        }
        address token1 = launchInfo.tokenAddress;
        address factory = launchInfo.router.factory();

        if (IUniswapV2Factory(factory).getPair(token0, token1) == address(0)) {
            IUniswapV2Factory(factory).createPair(token0, token1);
        }
            return true; 
    }

    function calculatePlatformShare(uint256 _amountRaised) public view returns(uint256) {
        uint256 platformFeeAmount = _amountRaised.mul(platformFee).div(1000);//multiplied with platformfee and divided with 1000

        return platformFeeAmount;
    }

    // if owner cancel the pool, he will get all his tokens back, and cannot 
    // claim any payment tokens
    function cancelPool() external onlyOwner {
        //we can add a require for cancelled in an if statement if needed
        require(poolData.status == PoolStatus.ACTIVE, "Already finalized or cancelled");

        poolData.status = PoolStatus.CANCELED;
        uint256 tokensForSale = IERC20(launchInfo.tokenAddress).balanceOf(address(this));
        IERC20(launchInfo.tokenAddress).transfer(msg.sender, tokensForSale);
         emit poolCancelled(msg.sender);
        // if renonce ownership is implemented, then it will be good
    }

    function addNativeLiquidity(uint256 tokenAmount, uint256 ethAmount) private {

        // approve token transfer to cover all possible scenarios
        ERC20(launchInfo.tokenAddress).approve(address(launchInfo.router), tokenAmount);

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
        ERC20(launchInfo.tokenAddress).approve(address(launchInfo.router), token0Amount);
        ERC20(launchInfo.paymentToken).approve(address(launchInfo.router), token1Amount);

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

   
    function claimLP() external onlyOwner {
        require(poolData.status == PoolStatus.COMPLETED, "Pool not completed");
        require(dexInfo.liquidityLockTime > block.timestamp, "LP locked");
        //  //if payment token is bnb(address 0) then it will take our native token
        address token0;
        if(launchInfo.paymentToken == address(0)){
            token0 = launchInfo.router.WETH(); 
        }else{
            token0 = launchInfo.paymentToken;
        }
        address token1 = launchInfo.tokenAddress;
        address factory = launchInfo.router.factory();
        address pairAddress = IUniswapV2Factory(factory).getPair(token0, token1);

        uint256 balance = ERC20(pairAddress).balanceOf(address(this));
        require(balance > 0, "Insufficient LP balance");

        ERC20(pairAddress).safeTransfer(msg.sender, balance);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}