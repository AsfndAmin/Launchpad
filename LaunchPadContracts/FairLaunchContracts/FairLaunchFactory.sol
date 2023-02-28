// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;
import "./DecentrapadFairLaunch.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract DecentraFairLaunchFactory {
    using SafeERC20 for ERC20;
    using SafeMath for uint256;
 

    event launchpadAddress(address _poolAddress);
    // need to add check when user enters the data about rates and tokens for liquidity and pool.
    // revert if tokens for LP * rate > (tokens for sale * preSale rate) + platform fee
    function deployPool(
        DecentrapadFairLaunch.launchSaleInfo memory _launchInfo,
        DecentrapadFairLaunch.dexListingInfo memory _listingInfo,
        address owner,
        bool _listingDex
    ) external {
        uint256 totalTokensRequired = _launchInfo.tokensForSale.add(_listingInfo.maxTokensForLiquidity);
        DecentrapadFairLaunch decentraPool = new DecentrapadFairLaunch(
            _launchInfo,
            _listingInfo,
            owner,
            _listingDex
            
        );
        ERC20(_launchInfo.tokenAddress).safeTransferFrom(msg.sender, address(decentraPool), totalTokensRequired);
        emit launchpadAddress(address(decentraPool));
    }
}