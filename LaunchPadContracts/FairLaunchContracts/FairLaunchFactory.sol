// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.10;
import "./DecentrapadFairLaunch.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract DecentraFairLaunchFactory is AccessControl, ReentrancyGuard{
    using SafeERC20 for ERC20;
    using SafeMath for uint256;
 
    event poolDeployed(address _poolAddress, address _owner);

    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    address platformAddress;
    uint256 platformOneTimeFee;
    uint256 base = 1000;
    uint8 nativeFee;
    uint8 dualFees; 


        constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(EXECUTOR_ROLE, msg.sender);
    }

    function deployPool(
        DecentrapadFairLaunch.launchSaleInfo memory _launchInfo,
        DecentrapadFairLaunch.dexListingInfo memory _listingInfo,
        address owner,
        bool feesInNative, 
        bool _maxContribution
    ) external nonReentrant payable{
                require(
            msg.value == platformOneTimeFee,
            "Invalid Pool Creation Fee sent"
        );

        uint256 totalTokensRequired;
        DecentrapadFairLaunch.poolFee memory _poolFee;

        if (feesInNative) {
            _poolFee = DecentrapadFairLaunch.poolFee(nativeFee, 0);
            totalTokensRequired = calculateTotalForNative(_launchInfo.tokensForSale, nativeFee, _listingInfo.lpTokensRatio);
        } else {
            _poolFee = DecentrapadFairLaunch.poolFee(dualFees, dualFees);
            totalTokensRequired = calculateTotalForDual(_launchInfo.tokensForSale, dualFees, _listingInfo.lpTokensRatio);
        } 
        
        DecentrapadFairLaunch decentraPool = new DecentrapadFairLaunch(
            _launchInfo,
            _listingInfo,
            _poolFee, 
            owner,
            _maxContribution,
            platformAddress
        );

        ERC20(_launchInfo.tokenAddress).safeTransferFrom(msg.sender, address(decentraPool), totalTokensRequired);
        payable(platformAddress).transfer(msg.value);
        emit poolDeployed(address(decentraPool), owner);
    }

    function calculateTotalForNative(uint256 _tokensForSale, uint256 _fee, uint256 _lpTokenRatio) public view returns(uint256){
        uint256 tokensForLP = _tokensForSale.mul(_lpTokenRatio).div(base);
        uint256 calculate =  tokensForLP.mul(_fee).div(base);
        uint256 tokensAfterFee = tokensForLP.sub(calculate);
        uint256 totalTokensRequired = _tokensForSale.add(tokensAfterFee);
        return totalTokensRequired;
    }

    function calculateTotalForDual(uint256 _tokensForSale, uint256 _dualFee, uint256 _lpTokenRatio) public view returns(uint256){
        uint256 tokensForLP = _tokensForSale.mul(_lpTokenRatio).div(base);
        uint256 feeTokensToAdd = _tokensForSale.mul(_dualFee).div(base);
        uint256 feeTokensToSub = tokensForLP.mul(_dualFee).div(base); 
        uint256 totalTokensRequired = ((_tokensForSale.add(tokensForLP)).add(feeTokensToAdd)).sub(feeTokensToSub);
        return totalTokensRequired;
    }

    function setPoolFees(uint8 _native, uint8 _dualFees)
        external
        onlyRole(EXECUTOR_ROLE)
    {
        nativeFee = _native;
        dualFees = _dualFees;
    }

    function setPlaformAddress(address newAddress)
        external
        onlyRole(EXECUTOR_ROLE)
    {
        platformAddress = newAddress;
    }

    function setPlaformFee(uint256 newFee) external onlyRole(EXECUTOR_ROLE) {
        platformOneTimeFee = newFee;
    }

    function getPlatformAddress() external view returns (address) {
        return platformAddress;
    }



}
