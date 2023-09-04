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
