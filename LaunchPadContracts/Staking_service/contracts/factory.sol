// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.7;
import "./TimeLockNonTransferablePool.sol";

contract Factory {

        event TimeLockNonTransferablePoolAdress(address _poolAddress);

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

}