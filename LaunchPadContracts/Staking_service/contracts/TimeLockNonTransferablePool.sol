// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "./TimeLockPool.sol";

contract TimeLockNonTransferablePool is TimeLockPool {
    constructor(
        address _owner,
        string memory _name,
        string memory _symbol,
        address _depositToken,
        address _rewardToken
    ) TimeLockPool(_owner, _name, _symbol, _depositToken, _rewardToken) {}

    // disable transfers
    function _transfer(
        address _from,
        address _to,
        uint256 _amount
    ) internal override {
        revert("NON_TRANSFERABLE");
    }
}
