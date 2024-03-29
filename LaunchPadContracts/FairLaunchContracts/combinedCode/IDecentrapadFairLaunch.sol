// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

interface IDecentrapadFairLaunch {
    
    enum PoolStatus {
        ACTIVE,
        CANCELED,
        COMPLETED
    }

    event UserInvestment(address indexed user, uint256 amount);

     event TokensBought(address user, address refferal, uint256 amount);
    event tokensClaimed(address user, uint256 amount, PoolStatus);
    event poolCancelled(address user);
    event ReferRewardsClaimed(address user, uint256 amount);
    event affiliateEnabled(uint256 ratio);
    event poolFinalized(uint256 totalRaised);


    function buyTokens(address referAddress, uint256 paymentAmount)
        external
        payable;

    function userClaim() external;

    function finalizeLaunch() external;

    function claimReferReward() external;

    function cancelPool() external;

}
