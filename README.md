## Staking Pools
A repo of single-sided staking pools.

Repo contains staking pools utilising 2 different mechanisms: 
1) StakingPoolIndex: the index mechanism, similar to lending protocols for tracking interest accumulation
2) StakingPoolShares: vault shares and ex-rate. auto-compounding is implemented naturally.

StakingPoolIndex, by nature of the index mechanism allows for a staking pool that can be initialized to be auto-compounding or linear.
- In auto-compounding mode, a user's previously accrued reawards are taken into account during future distribution of rewards.
- In linear mode, only users' principle stakes are accounted for during reward distribution.

StakingPoolShares
- has auto-compounding baked into it.
> If anyone has an elegant suggestion for how this approach can allow for both auto-compounding and linear distribution, please let me know.

## Design

I wanted the pools to be deployed allowing for set & forget approach; meaning they could be deployed in advance, configured to activate some time in the future.
Hence, the use of `_startTime`. Having the pools go directly into active mode on deployment or calling setUp seemed messy, with lesser control.

Upon activation, `block.timestamp > _startTime`, the pool would emit rewards to stakers. If there are no stakers, emitted rewards will be forgone; they will not accrued to the first staker, at whatever time that may be.
This seemed sensible from the perspective of "This pool begins at X time, and will emit Y rewards for Z seconds". 

### Index
The index is simply the total emission per token, for the entire duration of staking. It is calculated differently, depending on the mode of the pool.
I will use simple examples to illustrate the core of both modes.

#### Linear mode
Simply put, in linear mode, to get what is due to a user: (assetIndex - userIndex) * userStakedAmount
- assume he stakes only once
- ignore precision balancing

His userIndex == assetIndex, at the time of his stake; (assetIndex - userIndex) then is the summation of rewardsPerToken, from the moment he stakes to whenever he claims/withdraws.
This formula is similar to how linear interest is calculated: I = P(rt), where rt is the summation of rewardsPerToken for the user. 

-  P(rt) == P(eps/totalStaked)

In a multi-period setting, where totalStaked fluctutates every second:

Assume emissionPerSecond, eps is constant,
```
rewards =  P[eps/totalStaked@1 + eps/totalStaked@2 + ps/totalStaked@3 + ... ]       
        =  P[ k(eps/totalStaked@0-k) + j(eps/totalStaked@k+1-j+1) + ... ]      
```
where, totalStaked is constant from t=0 to t=k, and totalStaked changes at t=k+1 and is constant till t=j.

Thus, instead of updating rewardsPerToken(index) every second, we simply need to update it when totalStaked changes. 
For the user that is subject to causing this change, by either deposit/withdraw/claiming, his prior rewards are accounted for and recorded in a mapping, and his userIndex updated to the lastest assetIndex to reflect a new beginning.
Essentially, we 'close the book' on the past, and begin accounting for a new period due to changes. 

```solidity
            nextAssetIndex = ((emissionPerSecond * timeDelta * 10 ** PRECISION) / totalBalance) + currentAssetIndex;

```

### On Auto-compounding with Index:

```solidity
            _calculateAssetIndex(){
                ...
                uint256 timeDelta = currentTimestamp - lastUpdateTimestamp;

                ...
                uint256 emissionPerShareForPeriod = emissionPerSecond * timeDelta * 10 ** PRECISION / totalBalance;
                nextAssetIndex = (emissionPerShareForPeriod + 1e18) * currentAssetIndex / 10 ** PRECISION;

                ...
            }
```
In linear mode, we see that the index is simply 



## Testing