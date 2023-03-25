// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

interface ITimeLockPool {
    function deposit(uint256 _amount, address _receiver) external;
}
