// SPDX-License-Identifier: MIT
pragma solidity 0.8.7;

import "./TimeLockPool.sol";


/// @dev reader contract to easily fetch all relevant info for an account
contract View {

    struct Data {
        Pool[] pools;
    }

    struct Deposit {
        uint256 amount;
        uint64 start;
        uint64 end;
        uint256 multiplier;
    }

    struct Pool {
        address poolAddress;
        uint256 totalPoolShares;
        address depositToken;
        uint256 accountPendingRewards;
        uint256 accountClaimedRewards;
        uint256 accountTotalDeposit;
        uint256 accountPoolShares;
        Deposit[] deposits;
    }

    address[1] stakingPool;


    constructor(address[] memory _pools) { 
        for(uint8 i = 0; i <stakingPool.length; i++) {
            stakingPool[i] = _pools[i];
        }
    }

    function fetchData(address _account) external view returns (Data memory result) {

        result.pools = new Pool[](stakingPool.length);

        for(uint256 i = 0; i < stakingPool.length; i ++) { 

            TimeLockPool poolContract = TimeLockPool(stakingPool[i]);

            result.pools[i] = Pool({
                poolAddress: address(stakingPool[i]),
                totalPoolShares: poolContract.totalSupply(),
                depositToken: address(poolContract.depositToken()),
                accountPendingRewards: poolContract.withdrawableRewardsOf(_account),
                accountClaimedRewards: poolContract.withdrawnRewardsOf(_account),
                accountTotalDeposit: poolContract.getTotalDeposit(_account),
                accountPoolShares: poolContract.balanceOf(_account),
                deposits: new Deposit[](poolContract.getDepositsOfLength(_account))
            });

            TimeLockPool.Deposit[] memory deposits = poolContract.getDepositsOf(_account);

            for(uint256 j = 0; j < result.pools[i].deposits.length; j ++) {
                TimeLockPool.Deposit memory deposit = deposits[j];
                result.pools[i].deposits[j] = Deposit({
                    amount: deposit.amount,
                    start: deposit.start,
                    end: deposit.end,
                    multiplier: poolContract.getMultiplier(deposit.end - deposit.start)
                });
            }

            
        }

       
        

    }

}