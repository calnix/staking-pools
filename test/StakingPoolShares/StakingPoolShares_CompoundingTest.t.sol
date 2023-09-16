// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import { StakingPoolShares } from "../../src/Shares/StakingPoolShares.sol";
import { OwnableUpgradeable } from "../../src/Shares/StakingPoolShares.sol";

import "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

/**
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
    
 */

abstract contract StateZero is Test {
    ERC20Mock public baseToken;
    StakingPoolShares public stakingPool;

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

        rewards = 12 ether;
        startTime = 1;
        duration = 12 seconds;
        isAutoCompounding = true;

        userAPrinciple = 10 ether;
        userBPrinciple = 10 ether; 
        userCPrinciple = 80 ether; 

        vm.warp(0);
        vm.startPrank(owner);
        
        //deploy contracts
        baseToken = new ERC20Mock();
        stakingPool = new StakingPoolShares();
        stakingPool.initialize(IERC20(baseToken), dummyVault, owner);

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
        assertEq(baseToken.allowance(userB, address(stakingPool)), userBPrinciple);

        vm.prank(userC);
        baseToken.approve(address(stakingPool), userCPrinciple);
        
        // approval for issuing reward tokens to stakers
        vm.prank(dummyVault);
        baseToken.approve(address(stakingPool), rewards);

        vm.prank(owner);
        stakingPool.setUp(startTime, duration, rewards, isAutoCompounding);

        //check pool
        assertEq(stakingPool.getDistributionStart(), 1);
        assertEq(stakingPool.getDistributionEnd(), 1 + duration);
        assertEq(stakingPool.getEmissionPerSecond(), 1 ether);
        assertEq(stakingPool.getIsAutoCompounding(), isAutoCompounding);
        // check time
        assertEq(block.timestamp, 0);
    }
}

//Note: t0, Pool is deployed and setUp
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

        //staking begins
        vm.warp(1); 
    }
}

//Note: t1, startTime. Staking can begin, but no one stakes.
//     1e18 rewards harvested, but discarded and not emitted as there are no stakers.
//     See testRewardsHarvestedVsEmitted() at end.

/*
contract StateT01Test is StateT01 { 
//     placeholder
}
*/

abstract contract StateT02 is StateT01 {
    function setUp() public virtual override {
        super.setUp();

        vm.warp(2); 

        vm.prank(userA);
        stakingPool.stake(userA, userAPrinciple);

        assertEq(stakingPool.getUserPrinciple(userA), userAPrinciple);
        assertEq(stakingPool.getUserShares(userA), userAPrinciple);
    }
}

//Note: t2, startTime. Staking can begin. userA is first to stake.
contract StateT02Test is StateT02{
    function testOwnerCannotSetupAgain() public {
        vm.prank(owner);

        vm.expectRevert("Already setUp");
        stakingPool.setUp(1, 10 seconds, 1 ether, true);
    }

    function testCannotClaim() public {
        vm.prank(userA);
        
        stakingPool.getTotalStaked();
        stakingPool.getTotalRewards();

        vm.expectRevert("No rewards");
        stakingPool.claim(userA, type(uint256).max);
    }

    function testCanUnstake() public {
        
        // check principal and shares
        assertEq(stakingPool.getUserPrinciple(userA), userAPrinciple);
        assertEq(stakingPool.getUserShares(userA), userAPrinciple);

        vm.prank(userA);
        stakingPool.unstake(userA, userAPrinciple);

        assertEq(baseToken.balanceOf(userA), userAPrinciple);
    }

    function testRewardsAndShareCount() public {
        assertEq(stakingPool.getTotalShares(), 10e18);
        assertEq(stakingPool.getTotalRewards(), 0);
        assertEq(stakingPool.getTotalRewardsHarvested(), 1e18);
        assertEq(stakingPool.getLastUpdateTimestamp(), 2);

    }
}

//Note: 10 seconds passed since startTime. 10 rewards emitted.
abstract contract StateT12 is StateT02 {

    function setUp() public virtual override {
        super.setUp();

        vm.warp(12);        

        /**Note:
            A: 10e18 shares 
            totalStaked: 10e18 (frm A)

            totalRewards: 10e18 (on B calling stake => harvest() will update)            
            totalAssets = totalRewards + totalStaked = 20e18
           
            ex.rate => shares : asset == 1 : 2  

            userB shares: userBPrinciple * totalShares / (totalRewards + totalStaked)
            userB shares: 10e18 * 10e18 / (20e18) => 5e18 (5 shares)
         **/
        
        // stake at t=12
        vm.prank(userB);
        stakingPool.stake(userB, userBPrinciple);

        assertEq(stakingPool.getUserPrinciple(userB), userBPrinciple);
        assertEq(stakingPool.getUserShares(userB), 5e18);

        assertEq(stakingPool.getLastUpdateTimestamp(), 12);
    }
}

contract StateT12Test is StateT12 {

    function testTotalShares() public {
        //A: 10e18 shares, B: 5e18
        
        assertEq(stakingPool.getTotalShares(), 15e18);

        assertEq(stakingPool.getUserShares(userB), 5e18);
        assertEq(stakingPool.getUserShares(userA), 10e18);
    }

    function testTotalRewardsEmitted() public {
        // 10 seconds passed, 10 tokens emitted
        uint256 totalRewards = stakingPool.getTotalRewards();   
        assertEq(totalRewards, 10e18);
    }

    function testTotalStaked() public {
        //10e18 frm A and B each
        uint256 totalStaked = stakingPool.getTotalStaked();     
        assertEq(totalStaked, (userAPrinciple + userBPrinciple));

        assertEq(stakingPool.getUserPrinciple(userA), userAPrinciple);
        assertEq(stakingPool.getUserPrinciple(userB), userBPrinciple);
    }

    function testClaimRewards() public {
        // get system calculated rewards
        uint256 userARewards = stakingPool.getUserRewards(userA);
        uint256 userBRewards = stakingPool.getUserRewards(userB);

        // get system data
        uint256 totalShares = stakingPool.getTotalShares();
        uint256 totalRewards = stakingPool.getTotalRewards();
        uint256 totalStaked = stakingPool.getTotalStaked();

        assertEq(totalShares, 15e18);                   //15 shares
        assertEq(totalRewards, 10e18);                  //10 rewards emitted    
        assertEq(totalRewards + totalStaked, 30e18);    //30 asset tokens

        vm.prank(userA);
        stakingPool.claim(userA, type(uint256).max);

        vm.prank(userB);
        vm.expectRevert("No rewards");
        stakingPool.claim(userB, type(uint256).max);

        //totalShares = 15
        //totalAsset = _totalRewards + _totalStaked = 30
        //Ex.rate => 1 share : 2 asset

        //user A position: 10 * 2 = 20 tokens (10 rewards, 10 principal)
        //user B position: 5 * 2 = 10 tokens (0 rewards, 10 principal)
        assertEq(baseToken.balanceOf(userA), 10e18); // claim only applies to rewards
        assertEq(baseToken.balanceOf(userB), 0); 

        assertEq(baseToken.balanceOf(userA), userARewards);
        assertEq(baseToken.balanceOf(userB), userBRewards);
    }
}

//Note: 11 seconds passed since startTime. 11 rewards emitted.
abstract contract StateT13 is StateT12 {

    function setUp() public virtual override {
        super.setUp();
       
        // staking ended
        vm.warp(15);
    }
}

contract StateT13Test is StateT13 {

    function testRewardsAtEnd() public {

        // get system calculated rewards
        uint256 userARewards = stakingPool.getUserRewards(userA);
        uint256 userBRewards = stakingPool.getUserRewards(userB);

        vm.prank(userA);
        stakingPool.claim(userA, type(uint256).max);

        vm.prank(userB);
        stakingPool.claim(userB, type(uint256).max);

        //totalShares = 15
        //totalAsset = _totalRewards + _totalStaked = 11 + 20 = 31 
        //Ex.rate => 15 shares : 31 assets

        //user A assets: 10 * 31 / 15 = 20.667 tokens (10.667 rewards, 10 principal)
        //user B assets: 5 * 31 / 15 = 10.333 tokens (0.333 rewards, 10 principal)

        //division for rounding 
        assertEq(baseToken.balanceOf(userA) / 1e15, 10.666e18 / 1e15);          // 3dp
        assertEq(baseToken.balanceOf(userB) / 1e14, 3.333e17 / 1e14);           // 3dp

        assertEq(baseToken.balanceOf(userA), userARewards);
        assertEq(baseToken.balanceOf(userB) / 1e14, userBRewards / 1e14);       // rounding issue
    }

    function testUnstake() public {
        
        vm.prank(userA);
        stakingPool.unstake(userA, type(uint256).max);

        vm.prank(userB);
        stakingPool.unstake(userB, type(uint256).max);

        //division for rounding 
        assertEq(baseToken.balanceOf(userA), 10e18);          
        assertEq(baseToken.balanceOf(userB), 10e18);     
    }

    function testRewardsHarvestedVsEmitted() public {
        uint256 rewardsHarvested = stakingPool.getTotalRewardsHarvested();
        uint256 rewardsEmitted = stakingPool.getTotalRewards();

        uint256 delta = rewardsHarvested - rewardsEmitted;

        assertGe(rewardsHarvested, rewardsEmitted);
        assertEq(delta, 1e18);      
    }
}