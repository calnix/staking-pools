// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {AutoPool} from "../src/AutoPool.sol";

import "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";


abstract contract StateZero is Test {
    ERC20Mock public baseToken;
    AutoPool public stakingPool;

    address public userA;
    address public userB;
    address public userC;

    address public owner;

    address public dummyVault;

    uint256 public duration;
    uint256 public rewards;

    uint256 public userAPrinciple;
    uint256 public userBPrinciple;
    uint256 public userCPrinciple;

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
        userC = address(0xC);

        owner = address(0xABCD);
        dummyVault = address(0x1);

        rewards = 10 ether;
        duration = 10 seconds;

        userAPrinciple = 50 ether;
        userBPrinciple = 30 ether; 
        userCPrinciple = 80 ether; 

        vm.startPrank(owner);
        
        //deploy contracts
        baseToken = new ERC20Mock();
        stakingPool = new AutoPool();
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

        vm.warp(0);
        vm.prank(owner);
        stakingPool.setUp(duration, rewards, true);

        vm.prank(userA);
        stakingPool.stake(userA, userAPrinciple);

        vm.prank(userB);
        stakingPool.stake(userB, userBPrinciple);

        assertEq(stakingPool._startTime(), 0);
        assertEq(stakingPool._endTime(), 10);

    }
}

abstract contract State9 is StateZero {

    function setUp() public override {
        super.setUp();

        vm.warp(9);

    }
}

//Note: Pool deployed, to be configured. 
contract State9Test is State9 {


    function testOwnerCanConfig() public {


        vm.prank(userA);
        stakingPool.claim(userA, type(uint256).max);

        vm.prank(userB);
        stakingPool.claim(userB, type(uint256).max);

        assertEq(baseToken.balanceOf(userA), 0.625 ether); //3.328e16
        assertEq(baseToken.balanceOf(userA), 0.625 ether); //3.328e16

    }


}

/*

abstract contract State11 is State9 {

    function setUp() public override {
        super.setUp();

        //uint256 newindex = stakingPool._calculateAssetIndex(1e18, stakingPool._emissionPerSecond(), stakingPool._lastUpdateTimestamp(), 80 ether);
        //console2.log(newindex);

        vm.prank(userC);
        stakingPool.stake(userC, userCPrinciple);
        
        assertEq(stakingPool._totalRewardsStaked(), 9 ether);
        assertEq(stakingPool.totalSupply(), userAPrinciple+userBPrinciple+userCPrinciple);
        assertEq(stakingPool._assetIndex(), 1.125e17);
        

        vm.warp(11);
    }
}

contract State11Test is State11 {

        function testRewards() public {

        vm.prank(userA);
        stakingPool.claim(userA, type(uint256).max);

        vm.prank(userB);
        stakingPool.claim(userB, type(uint256).max);

        vm.prank(userC);
        stakingPool.claim(userC, type(uint256).max);

        assertEq(stakingPool._assetIndex(), 6.646e14);

        assertEq(baseToken.balanceOf(userC), 0.5 ether);
        assertEq(baseToken.balanceOf(userB), 0.1875 ether); //1.997e16
        assertEq(baseToken.balanceOf(userA), 0.3125 ether); //3.328e16
    }
}*/