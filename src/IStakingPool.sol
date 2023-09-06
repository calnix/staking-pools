// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

interface IStakingPool {
    
    function initialize(IERC20 stakedToken, IERC20 rewardToken, address rewardsVault, address owner, string memory name, string memory symbol) external;
    function setUp(uint256 duration, uint256 amount, bool isCompounding) external;
    function stake(address user, uint256 amount) external;
    function claim(address to, uint256 amount) external;
    function unstake(address to, uint256 amount) external;
    function recoverERC20(address tokenAddress, uint256 amount) external;

    function getAssetIndex() external view returns(uint256);
    function getEmissionPerSecond() external view returns(uint128);
    function getLastUpdateTimestamp() external view returns(uint128);
    function getDistributionEnd() external view returns(uint256);
    function getIsCompounding() external view returns(bool);
    function getTotalRewardsStaked() external view returns(uint256);
    function getUserIndex(address user) external view returns(uint256);
    function getBookedRewards(address user) external view returns(uint256);
    function getClaimedRewards(address user) external view returns(uint256);
    function getTotalRewardsAccrued(address user) external view returns(uint256);
}