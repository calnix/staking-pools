// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import { ERC20Mock } from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { StakingPoolIndex } from "../../src/Index/StakingPoolIndex.sol";
import { StakingPoolProxy } from "../../src/Index/StakingPoolProxy.sol";
import { Factory } from "../../src/Index/Factory.sol";
import { RewardsVault } from "../../src/Index/RewardsVault.sol";
import { IStakingPool } from "./IStakingPool.sol";


abstract contract StateZero is Test {

    ERC20Mock public baseToken; 
    StakingPoolIndex public stakingPool;
    StakingPoolProxy public proxy;
    Factory public factory;

    address public userA;
    address public admin;
    address public moneyManager;
    
    //deployment variables
    IERC20 public stakedToken; 
    IERC20 public rewardToken; 
    string public name;
    string public symbol;
    uint256 public salt;
    
    // contract addressess
    address poolAddress;
    address proxyAddress;
    address vaultAddress;

    // events
    event Deposit(address indexed from, uint256 amount);
    event Withdraw(address indexed to, uint256 amount);
    event Recovered(address indexed token, address indexed target, uint256 amount);
    event PoolInitiated(address indexed rewardToken, bool isCompounding, uint256 emission);

    function setUp() public virtual {
        
        userA = address(0xA);
        admin = address(0x1111);
        moneyManager = address(0x2222);

        vm.startPrank(admin);
        baseToken = new ERC20Mock();

        stakedToken = IERC20(address(baseToken)); 
        rewardToken = IERC20(address(baseToken)); 
        name = "stkMock";
        symbol = "stkM";
        salt = 1234;
        

        factory = new Factory(admin);
        // deploy batch
        (poolAddress, proxyAddress, vaultAddress) = factory.deploy(stakedToken, rewardToken, moneyManager, admin, name, symbol, salt);

        vm.stopPrank();

        //mint to moneyManager
        baseToken.mint(moneyManager, 20 ether);

    }
}

contract StateZeroTest is StateZero {

    //index should be incremented from 0 to 1
    function testIndexIncrementation() public {
        uint256 index = factory.index();

        assertEq(index, 1);
    }

    function testPrecomputePoolAddress() public {
 
        assertEq(poolAddress, factory.precomputePoolAddress(salt));
    }

    function testPrecomputeVaultAddress() public {

        assertEq(vaultAddress, factory.precomputeVaultByteCode(rewardToken, moneyManager, admin, salt));
    }

    function testPrecomputeProxyAddress() public {

        assertEq(proxyAddress, factory.precomputeProxyAddress(stakedToken, rewardToken, vaultAddress, poolAddress, admin, name, symbol, salt));
    }

    function testProxyInitialization() public {

        vm.expectRevert();
        IStakingPool(proxyAddress).initialize(stakedToken, rewardToken, vaultAddress, admin, name, symbol);
    }

}

abstract contract StateDeposit is StateZero {

    function setUp() public virtual override {
        super.setUp();

        vm.prank(moneyManager);
        baseToken.approve(vaultAddress, 20 ether);

    }
}

contract StateDepositTest is StateDeposit {

    function testDepositToVault() public {  
        vm.expectEmit(true, false, false, false);
        emit Deposit(moneyManager, 20 ether);

        vm.prank(moneyManager);
        RewardsVault(vaultAddress).deposit(moneyManager, 20 ether);

        assertEq(20 ether, rewardToken.balanceOf(vaultAddress));
        
    }
}


abstract contract StateSetup is StateDeposit {

    function setUp() public virtual override {
        super.setUp();

        vm.prank(moneyManager);
        RewardsVault(vaultAddress).deposit(moneyManager, 20 ether);

    }
}

contract StateSetupTest is StateSetup {

    function testPoolSetUp() public {
        vm.expectEmit(true, true, false, false);
        emit PoolInitiated(address(baseToken), true, 1 ether);
    
        vm.prank(admin);
        IStakingPool(proxyAddress).setUp(uint128(block.timestamp + 1), uint128(20 seconds), 20 ether, true);
        
        assertEq(true, IStakingPool(proxyAddress).getIsAutoCompounding());
        assertEq(1 ether, IStakingPool(proxyAddress).getEmissionPerSecond());
    }
}

abstract contract StateWithdraw is StateSetup {
    
    function setUp() public virtual override {
        super.setUp();
    }
}


contract StateWithdrawTest is StateWithdraw {
    
    function testWithdrawFromVault() public {  
        vm.expectEmit(true, false, false, false);
        emit Withdraw(moneyManager, 20 ether);

        vm.prank(moneyManager);
        RewardsVault(vaultAddress).withdraw(moneyManager, 20 ether);

        assertEq(20 ether, baseToken.balanceOf(moneyManager));
    }
}

abstract contract StateRandomToken is StateWithdraw {
    ERC20Mock public randomToken; 
        
    function setUp() public virtual override {
        super.setUp();

        vm.prank(admin);
        randomToken = new ERC20Mock();

        randomToken.mint(address(vaultAddress), 10 ether);
    }
}


contract StateRandomTokenTest is StateRandomToken {

    function testRecover() public {

        vm.prank(admin);
        RewardsVault(vaultAddress).recoverERC20(address(randomToken), admin, 10 ether);

        assertEq(10 ether, randomToken.balanceOf(admin));
    }
}