// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Storage contract for staking pool of index type
/// @author Calnix
/// @dev Meant to be inherited by pool logic
abstract contract StakingPoolIndexStorage {
    using SafeERC20 for IERC20;
 
    IERC20 public STAKED_TOKEN;  
    IERC20 public REWARD_TOKEN;
    address public REWARDS_VAULT;

    uint8 public constant PRECISION = 18;

    // Tracks unclaimed rewards accrued for each user
    mapping(address user => uint256 userindex) internal _userIndexes;

    // Tracks unclaimed rewards accrued for each user
    mapping(address user => uint256 accruedRewards) internal _accruedRewards;
    
    // Tracks claimed rewards
    mapping(address user => uint256 accruedRewards) internal _claimedRewards;

    // Asset data
    uint256 internal _assetIndex;
    uint128 internal _emissionPerSecond;
    uint128 internal _lastUpdateTimestamp;

    // Distribution Data
    bool internal _isAutoCompounding;           // enable compounding feature
    bool internal _isSetUp;                     // setUp() ran/or not 

    uint128 internal _startTime;                  // start time
    uint128 internal _endTime;                    // end time
    uint256 internal _totalRewardsStaked;         // total rewards unclaimed within pool


    // EVENTS
    event PoolInitiated(address indexed rewardToken, bool isCompounding, uint256 emission);
    event AssetIndexUpdated(address indexed asset, uint256 oldIndex, uint256 newIndex);
    event UserIndexUpdated(address indexed user, uint256 index);

    event Staked(address indexed from, address indexed onBehalfOf, uint256 amount);
    event Unstaked(address indexed from, address indexed to, uint256 amount);
    event RewardsAccrued(address user, uint256 amount);
    event RewardsClaimed(address indexed from, address indexed to, uint256 amount);
    event Recovered(address indexed token, uint256 amount);

}