// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { StakingPoolIndex } from "../../src/StakingPoolIndex.sol";
import { OwnableUpgradeable } from "../../src/StakingPoolIndex.sol";

import "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/**
    Scenario: Compounding Mode

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
 */


abstract contract StateZero is Test {
    ERC20Mock public baseToken;
    StakingPoolIndex public stakingPool;

    address public userA;
    address public userB;
    address public userC;

    address public owner;

    address public dummyVault;

    uint128 public startTime;
    uint128 public duration;
    uint256 public rewards;
    bool public isAutoCompounding;

    uint256 public userAPrinciple;
    uint256 public userBPrinciple;
    uint256 public userCPrinciple;

    //EVENTS
    event PoolInitiated(address indexed rewardToken, bool isAutoCompounding, uint256 emission);
    event AssetIndexUpdated(address indexed asset, uint256 index);
    event UserIndexUpdated(address indexed user, uint256 index);

    event Staked(address indexed from, address indexed onBehalfOf, uint256 amount);
    event Unstaked(address indexed from, address indexed to, uint256 amount);
    event RewardsAccrued(address user, uint256 amount);
    event RewardsClaimed(address indexed from, address indexed to, uint256 amount);
    event Recovered(address indexed token, uint256 amount);

    function setUp() public virtual {
        
        userA = address(0xA);
        userB = address(0xB);
        userC = address(0xC);

        owner = address(0xABCD);
        dummyVault = address(0x1);

        rewards = 10 ether;
        startTime = 1;
        duration = 10 seconds;
        isAutoCompounding = true;

        userAPrinciple = 50 ether;
        userBPrinciple = 30 ether; 
        userCPrinciple = 80 ether; 

        vm.warp(0);
        vm.startPrank(owner);
        
        //deploy contracts
        baseToken = new ERC20Mock();
        stakingPool = new StakingPoolIndex();
        stakingPool.initialize(IERC20(baseToken), IERC20(baseToken), dummyVault, owner, "StakedToken", "stkBT");

        //mint tokens
        baseToken.mint(userA, userAPrinciple);
        baseToken.mint(userB, userBPrinciple);
        baseToken.mint(userC, userCPrinciple);

        baseToken.mint(dummyVault, rewards);        // rewards for emission

        vm.stopPrank();

        // approvals for receiving tokens for staking
        vm.prank(userA);
        baseToken.approve(address(stakingPool), userAPrinciple);

        vm.prank(userB);
        baseToken.approve(address(stakingPool), userBPrinciple);

        vm.prank(userC);
        baseToken.approve(address(stakingPool), userCPrinciple);
        
        // approval for issuing reward tokens to stakers
        vm.prank(dummyVault);
        baseToken.approve(address(stakingPool), rewards);

        vm.prank(owner);
        stakingPool.setUp(startTime, duration, rewards, isAutoCompounding);

        //check pool
        assertEq(stakingPool.getDistributionStart(), 1);
        assertEq(stakingPool.getDistributionEnd(), 11);
        assertEq(stakingPool.getEmissionPerSecond(), 1 ether);
        assertEq(stakingPool.getIsAutoCompounding(), isAutoCompounding);
        // check time
        assertEq(block.timestamp, 0);
    }
}


contract StateZeroTest is StateZero {

    function testCannotStake() public {
        vm.prank(userA);
        vm.expectRevert("Not started");
        stakingPool.stake(userA, userAPrinciple);
    }

    function testCannotClaim() public {
        vm.prank(userA);
        vm.expectRevert("Not started");
        stakingPool.claim(userA, userAPrinciple);
    }

    function testCannotUnstake() public {
        vm.prank(userA);
        vm.expectRevert("Not started");
        stakingPool.unstake(userA, userAPrinciple);
    }

    function testUserCannotSetUp() public {
        vm.prank(userA);
        bytes memory errorMsg = abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, userA);
        vm.expectRevert(errorMsg);
        stakingPool.setUp(1, 10 seconds, 1 ether, true);
    }
}


abstract contract StateT01 is StateZero {

    function setUp() public virtual override {
        super.setUp();

        vm.warp(1);

        vm.prank(userA);
        stakingPool.stake(userA, userAPrinciple);

        vm.prank(userB);
        stakingPool.stake(userB, userBPrinciple);

        assertEq(stakingPool.balanceOf(userA), userAPrinciple);
        assertEq(stakingPool.balanceOf(userB), userBPrinciple);
    }
}

contract StateT01Test is StateT01 {
    function testOwnerCannotSetupAgain() public {
        vm.prank(owner);

        vm.expectRevert("Already setUp");
        stakingPool.setUp(1, 10 seconds, 1 ether, true);

    }

    function testCannotClaim() public {
        vm.prank(userA);

        vm.expectRevert("No rewards");
        stakingPool.claim(userA, type(uint256).max);
    }

    function testCanUnstake() public {

        assertEq(stakingPool.balanceOf(userA), userAPrinciple);
        assertEq(stakingPool.balanceOf(userB), userBPrinciple);

        vm.prank(userA);
        stakingPool.unstake(userA, userAPrinciple);

        vm.prank(userB);
        stakingPool.unstake(userB, userBPrinciple);

        assertEq(baseToken.balanceOf(userA), userAPrinciple);
        assertEq(baseToken.balanceOf(userB), userBPrinciple);
    }
}


abstract contract StateT10 is StateT01 {

    function setUp() public virtual override {
        super.setUp();

        vm.warp(10);
    }
}

//Note: Pool deployed, to be configured. 
contract StateT10Test is StateT10 {

    function testPhase1Rewards() public {
        uint256 getClaimedRewardsA = stakingPool.getUserRewards(userA);
        uint256 getClaimedRewardsB = stakingPool.getUserRewards(userB);

        vm.prank(userA);
        stakingPool.claim(userA, type(uint256).max);

        vm.prank(userB);
        stakingPool.claim(userB, type(uint256).max);

        // index = 1.1125e18
        assertEq(stakingPool.getTotalRewardsStaked(), 0 ether);
        assertEq(stakingPool.getassetIndex(), 1.1125e18); 

        //rewardPerShare = 0.1125
        //rewards earned A: 50 * 0.1125 = 5.625 tokens
        //rewards earned B: 30 * 0.1125 = 3.375 tokens
        assertEq(baseToken.balanceOf(userA), 5.625 ether); //correct
        assertEq(baseToken.balanceOf(userB), 3.375 ether); //correct

        assertEq(baseToken.balanceOf(userA), getClaimedRewardsA);
        assertEq(baseToken.balanceOf(userB), getClaimedRewardsB);
    }
}

abstract contract StateT11 is StateT10 {

    function setUp() public virtual override {
        super.setUp();

        vm.prank(userC);
        stakingPool.stake(userC, userCPrinciple);
        
        assertEq(stakingPool.getTotalRewardsStaked(), 9 ether);
        assertEq(stakingPool.totalSupply(), userAPrinciple+userBPrinciple+userCPrinciple);
        assertEq(stakingPool.getassetIndex(), 1.1125e18);
        
        // staking ended
        vm.warp(12);
    }
}

contract StateT11Test is StateT11 {

        function testRewards() public {
        
        uint256 getClaimedRewardsA = stakingPool.getUserRewards(userA);
        uint256 getClaimedRewardsB = stakingPool.getUserRewards(userB);
        uint256 getClaimedRewardsC = stakingPool.getUserRewards(userC);

        vm.prank(userA);
        stakingPool.claim(userA, type(uint256).max);

        vm.prank(userB);
        stakingPool.claim(userB, type(uint256).max);

        vm.prank(userC);
        stakingPool.claim(userC, type(uint256).max);
        
        //index = 1.119e18
        assertEq(stakingPool.getassetIndex() / 1e15, 1.119e18 / 1e15);      

        //division for rounding 
        assertEq(baseToken.balanceOf(userA) / 1e15, 5.954e18 / 1e15);       
        assertEq(baseToken.balanceOf(userB) / 1e15, 3.572e18 / 1e15);
        assertEq(baseToken.balanceOf(userC) / 1e14, 4.733e17 / 1e14);

        //rewards earned A: 5.625 + 0.329142 = 5.954e18
        //rewards earned B: 3.375 + 0.197485 = 3.572e18
        //rewards earned C: 0.473373 = 4.733e17

        assertEq(baseToken.balanceOf(userA), getClaimedRewardsA);
        assertEq(baseToken.balanceOf(userB), getClaimedRewardsB);
        assertEq(baseToken.balanceOf(userC), getClaimedRewardsC);

    }
}