// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.7;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./TimeLockNonTransferablePool.sol";


contract Factory is Initializable, UUPSUpgradeable, OwnableUpgradeable  { 

    event TimeLockNonTransferablePoolAdress(address _poolAddress);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() initializer public {
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    function deployPool(
        address _owner,
        string memory _name,
        string memory _symbol,
        address _depositToken,
        address _rewardToken
        ) external{
            TimeLockNonTransferablePool Pool = new TimeLockNonTransferablePool(
                _owner,
                _name,
                _symbol,
                _depositToken,
                _rewardToken
            );
            
    emit TimeLockNonTransferablePoolAdress(address(Pool)); 
            
        }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}
}