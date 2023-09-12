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


##### Other contracts
These contracts are not of heavy focus of this repo, but were created to illustrate functionality or in a supporting capacity.

- Factory: to batch deploy vault, proxy and pool via create2.
- Rewards Vault: simple contract to serve as illustration
- Proxy: to reflect UUPS upgradability

Disclaimer: Testing for these contracts were somewhat quick and dirty.

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
- ignore precision decimals

His userIndex == assetIndex, at the time of his stake; (assetIndex - userIndex) then is the summation of rewardsPerToken, from the moment he stakes to whenever he claims/withdraws.
This formula is similar to how linear interest is calculated: I = P(rt), where rt is the summation of rewardsPerToken for the user. 

-  P * [rt] == P * [`eps`/`totalStaked`]

In a multi-period setting, where totalStaked fluctutates every second:

Assume emissionPerSecond, eps is constant,
```solidity

// totalStaked at t=1 -> totalStaked@1, totalStaked at t=2 -> totalStaked@2

rewards =  P[eps/totalStaked@1 + eps/totalStaked@2 + ps/totalStaked@3 + ... ]       
        =  P[ k(eps/totalStaked@0-k) + j(eps/totalStaked@k+1-j+1) + ... ]      
```
where, totalStaked is constant from t=0 to t=k, and totalStaked changes at t=k+1 and is constant till t=j.

Thus, instead of updating rewardsPerToken(index) every second, we simply need to update it when totalStaked changes. 
For the user that is subject to causing this change, by either deposit/withdraw/claiming, his prior rewards are accounted for and recorded in a mapping, and his userIndex updated to the lastest assetIndex to reflect a new beginning.
Essentially, we 'close the book' on the past, and begin accounting for a new period due to changes. 

```solidity
_calculateAssetIndex(){
    ...
    nextAssetIndex = ((emissionPerSecond * timeDelta * 10 ** PRECISION) / totalBalance) + currentAssetIndex;
    ...
}

_calculateRewards(){
    ...
    (principalUserBalance * (assetIndex - userIndex)) / 10 ** PRECISION;
}

```

Notice, that the index is simply the summation of rewardsPerToken since inception. The index starts at 0, and increments like so:
```solidity
    Index = 0 + k(eps/totalStaked@0-k) + j(eps/totalStaked@k+1-j+1) + ... 
```

#### Auto-compounding mode
In auto-compounding mode, the index increments differently, and begins from 1.0

Recall the compounding interest formula: `C.I. = P(1 + r/n)**nt - P`, essentially we will implement this with the index.
On first pass, you may think that is needed is to alter the linear approach such that the index begins from 1.0 and instead of summation, multiplication is done.

Like so:
```solidity 
    
    lastIndex = currentIndex * j(eps/totalStaked@k+1-j+1)

    rewards = principalUserBalance * lastIndex/userIndex
```

However, imagine that the value of eps/totalStaked is 0.2; users get 0.2 tokens for each token staked. The timeseries sequence of the index by this approach would be: 1 * 0.2 * 0.2 * 0.2 * ...

This would result in the index decreasing due to decimal multiplication [`1 * 0.2 * 0.2 * 0.2 * = 0.008`]. 

This is clearly incorrect; the correct sequence should be something like this: [1 * 1.2 * 1.2 * ..].

We need to add a 1, which ultimately comes from the fact that you keep your base amount and not just the smaller interest amount.
if you earn 20% interest, 
- multiplying by 1.2 gives you the base + interest
- multiplying by 0.2 will only give you interest for that period.

A sequence of 1 * 0.2 * 0.2, would be the interest obtained at the start, subsequently applied to the consecutive interest for the following period; principal is discarded after the first period. 

If we want to repeatedly stack, or compound interest as it were, the addition of 1 is important. It's there to ensure that the end result is at least a 1 so that if you multiply it to your principle you get no less than what you started with as principle.
Otherwise you would get a final amount that can be less than what your principle started with originally.

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

Notice the addition of 1e18 to emissionPerShareForPeriod, this is reflective of our explanation earlier.

## Testing

### StakingPoolIndex: Compounding mode

####    Scenario: Compounding Mode

    ** Pool info **
    - stakingStart => t1
    - endStart => t11
    - duration: 10 seconds
    - emissionPerSecond: 1e18 (1 token per second)
    
    ** Phase 1: t1 - t10 **

    At t1: 
    userA and userB stake all of their principle
    - userA principle: 50 tokens (50e18)
    - userB principle: 30 tokens (30e18)

    totalStaked at t1 => 80 tokens

    At t10:
    calculating rewards:
    - timeDelta: 10 - 1 = 9 seconds 
    - rewards emitted since start: 9 * 1 = 9 tokens
    - rewardPerShare: 9e18 / 80e18 = 0.1125 

    rewards earned by A: 
    A_principle * rewardPerShare = 50 * 0.1125 = 5.625 rewards

    rewards earned by B: 
    B_principle * rewardPerShare = 30 * 0.1125 = 3.375 rewards

    
    ** Phase 1: t10 - t11 **

    At t10:
    userC stakes 80 tokens
    - Staking ends at t11
    - only 1 token left to be emitted to all stakers

    Principle staked
    - userA: 50 + 5.625 = 55.625e18
    - userB: 30 + 3.375 = 33.375e18
    - userC: 80e18

    totalStaked at t10 => 169e18 (80 + 9 + 80)tokens

    At11:
    calculating earned:
    - timeDelta: 11 - 10 = 1 second
    - rewards emitted since LastUpdateTimestamp: 1 * 1 = 1 token
    - rewardPerShare: 1e18 / 169e18 = 0.00591716

    rewards earned by A: 
    A_principle * rewardPerShare = 55.625e18 * 0.00591716 = 0.329142 rewards

    rewards earned by B: 
    B_principle * rewardPerShare = 33.375e18 * 0.00591716 = 0.197485 rewards
    
    rewards earned by C: 
    C_principle * rewardPerShare = 80e18 * 0.00591716 = 0.473372 rewards

####  Scenario: Linear Mode

    ** Pool info **
    - pool startTime: t1
    - stakingStart: t2
    - pool endTime: t12
    - duration: 11 seconds
    - emissionPerSecond: 1e18 (1 token per second)
    
    ** Phase 1: t0 - t1 **
    - pool deployed
    - pool inactive

    ** Phase 1: t1 - t2 **
    - pool active
    - no stakers
    - 1 reward emitted in this period, that is discarded.

    ** Phase 1: t2 - t11 **
    - userA and userB stake at t2
    - 9 rewards emitted in period

        At t2: 
        userA and userB stake all of their principle
        - userA principle: 50 tokens (50e18)
        - userB principle: 30 tokens (30e18)

        totalStaked at t2 => 80 tokens

        At t11:
        calculating rewards:
        - timeDelta: 11 - 2 = 9 seconds 
        - rewards emitted since start: 9 * 1 = 9 tokens
        - rewardPerShare: 9e18 / 80e18 = 0.1125 

        rewards earned by A: 
        A_principle * rewardPerShare = 50 * 0.1125 = 5.625 rewards

        rewards earned by B: 
        B_principle * rewardPerShare = 30 * 0.1125 = 3.375 rewards

    
    ** Phase 1: t11 - t12 **
    - userC stakes
    - final reward of 1 reward token is emitted at t12.
    - Staking ends at t12
    
        At t11:
        userC stakes 80 tokens
        
        - only 1 token left to be emitted to all stakers

        Principle staked
        - userA: 50 + 5.625 = 55.625e18
        - userB: 30 + 3.375 = 33.375e18
        - userC: 80e18

        totalStaked at t10 => 169e18 (80 + 9 + 80)tokens

        At12:
        calculating earned:
        - timeDelta: 12 - 11 = 1 second
        - rewards emitted since LastUpdateTimestamp: 1 * 1 = 1 token
        - rewardPerShare: 1e18 / 160e18 = 0.00625

        userA additional rewards: 50 * 0.00625 = 0.3125
        userA total rewards: 5.625 + 0.3125 = 5.9375

        userB additional rewards: 30 * 0.00625 = 0.1875
        userB total rewards: 3.375 + 0.1875 = 3.5625

        userC additional rewards: 80 * 0.00625 = 0.5
        userC total rewards: 0 + 0.5 = 0.5


### StakingPoolShares: Compounding mode

    Scenario: Compounding Mode

    ** Pool info **
    - stakingStart => t1
    - stakingEnd => t13
    - duration: 12 seconds
    - emissionPerSecond: 1e18 (1 token per second)
    
    ** Phase 1: t0 - t1 **
    - pool deployed
    - cannot stake/claim/unstake. 
    - pool activates on t1

    ** Phase 2: t1 - t2 **
    - pool is active.
    - 1 reward harvested. 
    - since no stakers, this reward is harvested but forgone.
    - tracked as _totalRewardsHarvested

    ** Phase 2: t2 - t12 (10 seconds)**
    - userA stakes 10e18 tokens.
    - userA get 10e18 shares.
    - _totalRewards: 10e18
    - _totalRewardsHarvested: 11e18  (1 from the earlier discarded reward)

    -> userA assets: 20
    -> userA rewards: 10

    ** Phase 2: t12 - t13 **
    - userB stakes 10e18 tokens.
    - userB get 5e18 shares.

    ** Phase 3: t13 **
    - final 1 reward distribution to both users.
    
    -> userA assets: 20.667
    -> userA rewards: 10.667

    -> userB assets: 10.333
    -> userB rewards: 0.333
    