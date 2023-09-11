// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { StakingPoolIndex } from "../../src/StakingPoolIndex.sol";
import { OwnableUpgradeable } from "../../src/StakingPoolIndex.sol";

import "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/**
    Scenario: Linear Mode

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

        rewards = 11 ether;
        startTime = 1;
        duration = 11 seconds;
        isAutoCompounding = false;

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
        assertEq(stakingPool.getDistributionEnd(), 12);
        assertEq(stakingPool.getEmissionPerSecond(), 1 ether);
        assertEq(stakingPool.getIsAutoCompounding(), isAutoCompounding);
        // check time
        assertEq(block.timestamp, 0);
    }
}

//Note: Pool deployed but not active yet.
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
    }
}

//Note: t=01, Pool deployed and active. But no one stakes.
//      discarded reward that is emitted.
//      see testDiscardedRewards() at the end.
contract StateT01Test is StateT01 {
    // placeholder
}

abstract contract StateT02 is StateT01 {

    function setUp() public virtual override {
        super.setUp();

        vm.warp(2);

        vm.prank(userA);
        stakingPool.stake(userA, userAPrinciple);

        vm.prank(userB);
        stakingPool.stake(userB, userBPrinciple);

        assertEq(stakingPool.balanceOf(userA), userAPrinciple);
        assertEq(stakingPool.balanceOf(userB), userBPrinciple);
    }
}

//Note: t=02, Pool deployed and active. userA and userB stake.
contract StateT02Test is StateT02 {
    function testOwnerCannotSetupAgain() public {
        vm.prank(owner);

        vm.expectRevert("Already setUp");
        stakingPool.setUp(1, 10 seconds, 1 ether, true);

    }

    //should be no rewards to claim
    function testCannotClaim() public {
        vm.prank(userA);

        vm.expectRevert("No rewards");
        stakingPool.claim(userA, type(uint256).max);

        vm.prank(userB);

        vm.expectRevert("No rewards");
        stakingPool.claim(userB, type(uint256).max);
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


abstract contract StateT11 is StateT02 {

    function setUp() public virtual override {
        super.setUp();

        vm.warp(11);
    }
}

//Note: t=02, Pool deployed and active. 9 rewards emitted to userA and userB.
contract StateT11Test is StateT11 {

    function testClaimRewards() public {
        uint256 getClaimedRewardsA = stakingPool.getUserRewards(userA);
        uint256 getClaimedRewardsB = stakingPool.getUserRewards(userB);

        vm.prank(userA);
        stakingPool.claim(userA, type(uint256).max);

        vm.prank(userB);
        stakingPool.claim(userB, type(uint256).max);

        /**
            calculating rewards:
            - timeDelta: 10 - 1 = 9 seconds 
            - rewards emitted since staked: 9 * 1 = 9 tokens
            - rewardPerShare: 9e18 / 80e18 = 0.1125 
            - Index: 1.125e17 (index represents rewardsPerShare since inception)
        */
    
        // index = 1.125e17
        assertEq(stakingPool.getTotalRewardsStaked(), 0 ether);
        assertEq(stakingPool.getassetIndex(), 1.125e17); 

        //rewardPerShare = 0.1125
        //rewards earned A: 50 * 0.1125 = 5.625 tokens
        //rewards earned B: 30 * 0.1125 = 3.375 tokens
        assertEq(baseToken.balanceOf(userA), 5.625 ether); //correct
        assertEq(baseToken.balanceOf(userB), 3.375 ether); //correct

        assertEq(baseToken.balanceOf(userA), getClaimedRewardsA);
        assertEq(baseToken.balanceOf(userB), getClaimedRewardsB);
    }
}

//Note: t=11, userC stakes. then progress to t=12
abstract contract StateT12 is StateT11 {

    function setUp() public virtual override {
        super.setUp();

        assertEq(block.timestamp, 11);

        vm.prank(userC);
        stakingPool.stake(userC, userCPrinciple);
        
        assertEq(stakingPool.getTotalRewardsStaked(), 0 ether);
        assertEq(stakingPool.totalSupply(), userAPrinciple+userBPrinciple+userCPrinciple);
        assertEq(stakingPool.getassetIndex(), 1.125e17);
        
        // staking ended
        vm.warp(15);
    }
}

//Note: t=12, 1 final reward emitted to userA, userB and userC.
contract StateT12Test is StateT12 {

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

        /**
            calculating rewards:
            - timeDelta: 1 second
            - rewards emitted since lastUpdate: 1 tokens
            - rewardPerShare: 1e18 / 160e18 = 0.00625                (Liner: div. by total principal staked)
            - Index: oldIndex + rewardsPerShare = 0.1125 + 0.00625   (index represents rewardsPerShare since inception)
            - Index: 0.1125 + 0.00625 = 0.11875 => 1.1875e17

            userA additional rewards: 50 * 0.00625 = 0.3125
            userA total rewards: 5.625 + 0.3125 = 5.9375

            userB additional rewards: 30 * 0.00625 = 0.1875
            userB total rewards: 3.375 + 0.1875 = 3.5625

            userC additional rewards: 80 * 0.00625 = 0.5
            userC total rewards: 0 + 0.5 = 0.5

        */
        
        //index = 1.1875e17
        assertEq(stakingPool.getassetIndex(), 1.1875e17);      
        
        // check system against calculated
        assertEq(baseToken.balanceOf(userA), 5.9375e18);       
        assertEq(baseToken.balanceOf(userB), 3.5625e18);
        assertEq(baseToken.balanceOf(userC), 0.5e18);

        // check getter function against calculated
        assertEq(baseToken.balanceOf(userA), getClaimedRewardsA);
        assertEq(baseToken.balanceOf(userB), getClaimedRewardsB);
        assertEq(baseToken.balanceOf(userC), getClaimedRewardsC);

    }

    // this accounts for the discarded reward from t1-t2, 
    // where pool was active but no one staked.
    function testDiscardedRewards() public {
        uint256 getClaimedRewardsA = stakingPool.getUserRewards(userA);
        uint256 getClaimedRewardsB = stakingPool.getUserRewards(userB);
        uint256 getClaimedRewardsC = stakingPool.getUserRewards(userC);

        uint256 totalUserRewards = getClaimedRewardsA + getClaimedRewardsB + getClaimedRewardsC;
        
        uint256 rewardsDelta = rewards - totalUserRewards;
        
        assertEq(totalUserRewards, 10 ether);      
        assertEq(rewardsDelta, 1 ether);      
    }

    function testCanUnstake() public {
        vm.prank(userA);
        stakingPool.unstake(userA, type(uint256).max);

        vm.prank(userB);
        stakingPool.unstake(userB, type(uint256).max);

        vm.prank(userC);
        stakingPool.unstake(userC, type(uint256).max);

        assertEq(baseToken.balanceOf(userA), userAPrinciple);       
        assertEq(baseToken.balanceOf(userB), userBPrinciple);
        assertEq(baseToken.balanceOf(userC), userCPrinciple);
    }
}
