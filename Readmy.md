Compounding
- shares capture the time dimension of staking
- For same capital, more shares at the start vs much later.

Linear
- need to have timestamp
- accrued rewards: principalUserBalance * (assetIndex - userIndex)
- delta{assetIndex}: emissionForPastPeriodPerShare
- booked rewards: 
- assetIndex is emission
((_emissionPerSecond * timeDelta * 10**18) / totalBalance) + currentAssetIndex


for linear, it comes down to time exposure.
- how many seconds were you staked for?
- cos emissionsPerShare is constant throughout
- NO! emissionsPerShare is not constant: eps is dividied out across totalStaked, which can change over time.
- the morsel you get is a function of totalStaked
- eps is fixed. 
- ++accruedPerShare -> emissionForPastPeriodPerShare
- 




Pool cannot be reused
- cos cannot clean out mappings, 