// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "../../forge-std/Test.sol";
import "../../src/Gamified/StakingPoolGamified.sol";

import {ERC20Mock} from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract StateZero is Test {
    ERC20Mock public baseToken;
    StakingPoolGamified public stakingPool;

    address public userA;
    address public userB;
    address public admin;

    address public vault;

    uint256 public duration;
    uint256 public rewards;

    uint256 public userAPrinciple;
    uint256 public userBPrinciple;

    bool public isCompounding;

    //EVENTS
    event PoolInitiated(address indexed rewardToken, bool isCompounding, uint256 emission);
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
        admin = address(0xAD);
        vault = address(0x1);

        rewards = 20 ether;
        duration = 20 seconds;
        isCompounding = false; 

        userAPrinciple = 400 ether;
        userBPrinciple = 100 ether; 

        vm.startPrank(admin);
        
        //deploy contracts
        baseToken = new ERC20Mock();
        stakingPool = new StakingPoolGamified();
        stakingPool.initialize(IERC20(baseToken), IERC20(baseToken), vault, admin, "stkMock", "stkM");

        //mint tokens
        baseToken.mint(userA, userAPrinciple);
        baseToken.mint(userB, userBPrinciple);
        baseToken.mint(vault, rewards);        // rewards for emission

        vm.stopPrank();

        // approvals for receiving tokens for staking
        vm.prank(userA);
        baseToken.approve(address(stakingPool), userAPrinciple);

        vm.prank(userB);
        baseToken.approve(address(stakingPool), userBPrinciple);
        
        // approval for issuing reward tokens to stakers
        vm.prank(vault);
        baseToken.approve(address(stakingPool), rewards);
    }
}

//Note: Pool deployed, to be setUp. 
contract StateZeroTest is StateZero {

    function testUserCannotSetUp() public {
        
        vm.prank(userA);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, userA));
        
        stakingPool.setUp(duration, rewards, isCompounding);
    }

    function testOwnerCanSetUp() public {
        vm.expectEmit(true, true, true, false);
        emit PoolInitiated(address(baseToken), true, rewards/duration);

        vm.prank(admin);
        stakingPool.setUp(duration, rewards, isCompounding);
    }

}

//Note: Pool has been setUp. Staking started.
abstract contract StateConfigured is StateZero {

    function setUp() public virtual override {
        super.setUp();

        vm.warp(1);

        vm.prank(admin);
        stakingPool.setUp(duration, rewards, isCompounding);
    }
}

contract StateSetUpTest is StateConfigured {

    function testCannotCallSetUpWhileActive() public {

        vm.prank(admin);
        vm.expectRevert("on-going distribution");
        stakingPool.setUp(duration * 2 , rewards * 2, isCompounding);
    }

    function testUserCannotReedem(uint256 amount, address to) public {
        vm.assume(amount > 0);
        vm.assume(to != address(0));

        vm.prank(userA);
        vm.expectRevert("Nothing staked");
        stakingPool.unstake(to, amount);
    }

    function testUserCannotClaim(uint256 amount, address to) public {
        vm.assume(amount > 0);
        vm.assume(to != address(0));

        vm.prank(userA);
        vm.expectRevert("No rewards");
        stakingPool.claim(to, amount);
    }

    function testUserCanStake() public {

        vm.prank(userA);
        stakingPool.stake(userA, userAPrinciple/2);

        //user has stkTokens
        assertEq(stakingPool.balanceOf(userA), userAPrinciple/2);
        //user has baseTokens
        assertEq(baseToken.balanceOf(userA), userAPrinciple/2);
    }

}   

//Note: userA stakes half his principle 5 seconds from setUp
abstract contract StateAStaked is StateConfigured {

    function setUp() public virtual override {
        super.setUp();

        vm.warp(6);

        vm.prank(userA);
        stakingPool.stake(userA, userAPrinciple/2);
    }
}

contract StateAStakedTest is StateAStaked {
    
    function testUserANothingToClaim(uint256 amount) public {
        vm.assume(amount > 0);
        
        vm.prank(userA);
        vm.expectRevert("No rewards");
        stakingPool.claim(userA, amount);

        assertEq(stakingPool.getBookedRewards(userA), 0);
    }

    function testCannotTransferSTKTokens() public {

        vm.prank(userA);
        vm.expectRevert("Staked token is not transferable");
        stakingPool.transfer(userB, userAPrinciple/2);
    }

    function testCannotTransferFromSTKTokens() public {

        vm.prank(userA);
        stakingPool.approve(userB, userAPrinciple/2);

        vm.prank(userB);
        vm.expectRevert("Staked token is not transferable");
        stakingPool.transferFrom(userA, userB, userAPrinciple/2);
    }

    function testUserACanUnstake(uint256 amount) public {
        vm.assume(amount > 0);
        vm.assume(amount <= userAPrinciple/2);

        vm.prank(userA);
        stakingPool.unstake(userA, amount);

        assertEq(baseToken.balanceOf(userA), userAPrinciple/2 + amount);
        assertEq(stakingPool.balanceOf(userA), userAPrinciple/2 - amount);
    }

    function testUserBCanStake() public {
        vm.prank(userB);
        stakingPool.stake(userB, userBPrinciple);

        assertEq(baseToken.balanceOf(userB), 0);
        assertEq(stakingPool.balanceOf(userB), userBPrinciple);  
    }

}

//Note: userB stakes all his principle 10 seconds from setUp
abstract contract StateBStaked is StateAStaked {

    function setUp() public virtual override {
        super.setUp();

        vm.warp(6 + 5);

        vm.prank(userB);
        stakingPool.stake(userB, userBPrinciple);
    }
}

contract StateBStakedTest is StateBStaked {

    function testUserBNothingToClaim(uint256 amount, address to) public {
        vm.assume(amount > 0);
        vm.assume(to != address(0));

        vm.prank(userB);
        vm.expectRevert("No rewards");
        stakingPool.claim(to, amount);
    } 

    function testUserACanClaim(uint256 rewardsToClaim) public {
        // rewards emitted since A staked: 
        uint256 rewardsEmitted = stakingPool.getEmissionPerSecond() * 5 seconds;     
        
        vm.assume(rewardsToClaim > 0);
        vm.assume(rewardsToClaim <= rewardsEmitted);
        
        vm.prank(userA);
        stakingPool.claim(userA, rewardsToClaim);  

        // staked amount unchanged
        assertEq(stakingPool.balanceOf(userA), userAPrinciple/2); 
        
        // rewards moved from Vault to userA
        assertEq(baseToken.balanceOf(userA), userAPrinciple/2 + rewardsToClaim); 
        assertEq(baseToken.balanceOf(vault), rewards - rewardsToClaim);

    }
}

//Note: userA stakes remaining half of his principle 15 seconds from setUp
abstract contract StateAStakedTwice is StateBStaked {

    function setUp() public virtual override {
        super.setUp();

        vm.warp(11 + 5);

        vm.prank(userA);
        stakingPool.stake(userA, userAPrinciple/2);
    }
}

contract StateAStakedTwiceTest is StateAStakedTwice {

    // A can unstake in full
    function testUserACanunstakeAll() public {
        vm.prank(userA);
        stakingPool.unstake(userA, userAPrinciple);
        
        assertEq(stakingPool.balanceOf(userA), 0);  
        assertEq(baseToken.balanceOf(userA), userAPrinciple);
    }

    // no rewards for latest stake. accrued rewards for prior stake.
    function testUserACanClaimRewardsForPriorStake() public {
        // A staked at 5 sec mark, B staked at 10 sec               
        // 1) From 5 - 10 second mark, A enjoys: all the rewards emitted. It is the sole stake.
        // 2) From 10 - 15 second mark, A enjoys: totalRewards * 0.5userAPrinciple / (0.5userAPrinciple + userBPrinciple)

        // rewards emitted: 5 - 10 second mark
        uint256 rewardsEmittedFirst = stakingPool.getEmissionPerSecond() * 5 seconds;     

        // rewards emitted: 10 - 15 second mark
        uint256 rewardsEmittedSecond = stakingPool.getEmissionPerSecond() * 5 seconds;  
        uint256 totalSupplyStaked = (userAPrinciple / 2) + userBPrinciple;

        uint256 rewardsToASecond = (rewardsEmittedSecond * userAPrinciple / 2) / totalSupplyStaked;

        uint256 rewardsToClaim = rewardsEmittedFirst + rewardsToASecond;

        vm.expectEmit(true, true, true, false);
        emit RewardsClaimed(userA, userA, rewardsToClaim);
        // event data should be in-line with calculated value
        vm.prank(userA);
        stakingPool.claim(userA, type(uint256).max); //8.333e18

        // staked amount unchanged - A has staked in full now
        assertEq(stakingPool.balanceOf(userA), userAPrinciple); 
        
        // rewards moved from Vault to userA
        assertEq(baseToken.balanceOf(userA) / 10**18, rewardsToClaim / 10**18); 
        assertEq(baseToken.balanceOf(vault) / 10**18, (rewards - rewardsToClaim) / 10**18);
    } 

    function testUserBCanClaimRewards() public {
        // A staked at 5 sec mark, B staked at 10 sec               
        // 1) From 5 - 10 second mark, A enjoys: all the rewards emitted. It is the sole stake.
        // 2) From 10 - 15 second mark, B enjoys: totalRewards * userBPrinciple / (0.5userAPrinciple + userBPrinciple)    

        // rewards emitted: 10 - 15 second mark
        uint256 rewardsEmittedSecond = stakingPool.getEmissionPerSecond() * 5 seconds;  
        uint256 totalSupplyStaked = (userAPrinciple / 2) + userBPrinciple;

        // rewards emitted since B stake
        uint256 rewardsToB = (rewardsEmittedSecond * userBPrinciple)/ totalSupplyStaked;
        
        vm.expectEmit(true, true, true, false);
        emit RewardsClaimed(userB, userB, rewardsToB);
        // event data should be in-line with calculated value
        vm.prank(userB);
        stakingPool.claim(userB, type(uint256).max); //1.666e18

        // staked amount unchanged - B has staked in full
        assertEq(stakingPool.balanceOf(userB), userBPrinciple); 
        
        // rewards moved from Vault to userA
        //Rebase to amountInTokens to ignore negligible rounding frm maunal calculation above
        assertEq(baseToken.balanceOf(userB) / 10**18, rewardsToB / 10**18); 
        assertEq(baseToken.balanceOf(vault) / 10**18, (rewards - rewardsToB) / 10**18);
    }
}

//Note: Distribution has ended, after 20 seconds. Everyone is staked.
abstract contract StateDistributionEnded is StateAStakedTwice {

    function setUp() public virtual override {
        super.setUp();

        vm.warp(16 + 5 + 1);    
    }
}

contract StateDistributionEndedTest is StateDistributionEnded {

    function testDistributionEnded() public {
        assertTrue(block.timestamp > stakingPool.getDistributionEnd());
    }
    
    function testUserBCanClaimAllRewards() public {

        // B stakes at 10 sec mark, A stakes again at 15 sec mark
        // 1) From 10 - 15 second mark, B enjoys: totalRewards * userBPrinciple / (userAPrinciple/2 + userBPrinciple)
        // 2) From 15 - 20 second mark, B enjoys: totalRewards * userBPrinciple / (userAPrinciple + userBPrinciple)

        // rewards emitted: 10 - 15 second mark
        uint256 rewardsEmittedFirst = stakingPool.getEmissionPerSecond() * 5 seconds;     
        uint256 rewardsToBFirst = rewardsEmittedFirst * userBPrinciple / (userAPrinciple/2 + userBPrinciple);

        // rewards emitted: 15 - 20 second mark
        uint256 rewardsEmittedSecond = stakingPool.getEmissionPerSecond() * 5 seconds;     
        uint256 rewardsToBSecond = rewardsEmittedSecond * userBPrinciple / (userAPrinciple + userBPrinciple);

        uint256 rewardsToClaim = rewardsToBFirst + rewardsToBSecond;
        
        vm.expectEmit(true, true, true, false);
        emit RewardsClaimed(userB, userB, rewardsToClaim);
        // event data should be in-line with calculated value
        vm.prank(userB);
        stakingPool.claim(userB, type(uint256).max); 

        // B's stkToken remain untouched
        assertEq(stakingPool.balanceOf(userB), userBPrinciple); 
        
        // rewards moved from Vault to userB. 
        //Rebase to amountInTokens to ignore negligible rounding frm maunal calculation above
        assertEq(baseToken.balanceOf(userB) / 10**18, rewardsToClaim / 10**18); 
        assertEq(baseToken.balanceOf(vault) / 10**18, (rewards - rewardsToClaim) / 10**18);
    }

    function testUserBCanunstake() public {
        vm.prank(userB);
        stakingPool.unstake(userB, userBPrinciple);
        
        assertEq(stakingPool.balanceOf(userB), 0);  
        assertEq(baseToken.balanceOf(userB), userBPrinciple);
    }

    function testUserACanClaimAllRewards() public {

        // A stakes at 5 sec mark, B stakes at 10 sec mark, A stakes again at 15 sec mark
        // 1) From 5 - 10 sec mark, A enjoys all rewards
        // 2) From 10 - 15 second mark, A enjoys: totalRewards * 0.5userAPrinciple / (0.5userAPrinciple + userBPrinciple)
        // 3) From 15 - 20 second mark, A enjoys: totalRewards * userAPrinciple / (userAPrinciple + userBPrinciple)

        // rewards emitted for each period
        uint256 rewardsEmittedPerPeriod = stakingPool.getEmissionPerSecond() * 5 seconds;     

        // rewards emitted: 5 - 10 sec mark
        uint256 rewardsEmittedFirst = rewardsEmittedPerPeriod;    

        // rewards emitted: 10 - 15 sec mark
        uint256 rewardsEmittedSecond = (rewardsEmittedPerPeriod * (userAPrinciple/2)) / (userAPrinciple/2 + userBPrinciple);

        // rewards emitted: 15 - 20 second mark
        uint256 rewardsEmittedThird = rewardsEmittedPerPeriod * userAPrinciple / (userAPrinciple + userBPrinciple);     
        
        // total rewards to userA
        uint256 rewardsToClaim = rewardsEmittedFirst + rewardsEmittedSecond + rewardsEmittedThird;
        
        vm.expectEmit(true, true, true, false);
        emit RewardsClaimed(userA, userA, rewardsToClaim);
        // event data should be in-line with calculated value
        vm.prank(userA);
        stakingPool.claim(userA, type(uint256).max); 

        // stkToken remain untouched
        assertEq(stakingPool.balanceOf(userA), userAPrinciple); 
        
        // rewards moved from Vault to user
        //Rebase to amountInTokens to ignore negligible rounding frm maunal calculation above
        assertEq(baseToken.balanceOf(userA) / 10**18, rewardsToClaim / 10**18); 
        assertEq(baseToken.balanceOf(vault) / 10**18, (rewards - rewardsToClaim) / 10**18);
    }

    function testRewardsBuffer() public { 
        vm.prank(userA);
        stakingPool.claim(userA, type(uint256).max); 

        vm.prank(userB);
        stakingPool.claim(userB, type(uint256).max); 

        //should only have 5 tokens left in vault
        assertEq(baseToken.balanceOf(vault) / 10**18, 5);
    }
}