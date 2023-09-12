// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import "forge-std/Test.sol";
import { ERC20Mock } from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { StakingPoolIndex } from "../../src/Index/StakingPoolIndex.sol";
import { StakingPoolProxy } from "../../src/Index/StakingPoolProxy.sol";
import { Factory } from "../../src/Index/Factory.sol";
import { IStakingPool } from "./IStakingPool.sol";

abstract contract StateZero is Test {

    ERC20Mock public baseToken; 
    StakingPoolProxy public proxy;
    Factory public factory;
    
    //users
    address public userA;
    address public userB;
    address public admin;
    address public moneyManager;

    //user balance
    uint256 public userABaseTokens;

    //deployment variables
    IERC20 public stakedToken; 
    IERC20 public rewardToken; 
    address public rewardsVault;
    string public name;
    string public symbol;
    uint256 public salt;
    
    // contract addressess
    address public poolAddress;
    address public proxyAddress;
    address public vaultAddress;

    event AssetsetUpUpdated(address indexed rewardToken, bool isCompounding, uint256 emission);
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
        admin = address(0x1111);
        moneyManager = address(0x2222);

        userABaseTokens = 10 ether;

        vm.prank(admin);
        baseToken = new ERC20Mock();

        vm.startPrank(admin);
      
        stakedToken = IERC20(address(baseToken)); 
        rewardToken = IERC20(address(baseToken)); 
        name = "stkMock";
        symbol = "stkM";
        salt = 1234;
        
        factory = new Factory(admin);
        // deploy batch
        (poolAddress, proxyAddress, vaultAddress) 
        = factory.deploy(stakedToken, rewardToken, moneyManager, admin, name, symbol, salt);

        proxy = StakingPoolProxy(payable(proxyAddress));
        vm.stopPrank();

        //mint to vault
        vm.prank(admin);
        baseToken.mint(vaultAddress, 30 * 30 ether);
        
        //approve to vault
        vm.prank(vaultAddress);
        baseToken.approve(proxyAddress, 30 * 30 ether);

        //mint to userA
        vm.prank(admin);
        baseToken.mint(userA, userABaseTokens);

        //approve to proxy
        vm.prank(userA);
        baseToken.approve(proxyAddress, userABaseTokens);

    }
}


contract StateZeroTest is StateZero {
//Note: pool deployed and initialized.

    function testImplementation() public {
        assertEq(proxy.implementation(), poolAddress);
    }


    function testCannotReInitialize() public {
        bytes memory payload = abi.encodeWithSignature("initialize(address,address,address,address,string,string)",
            address(baseToken), address(baseToken), vaultAddress, admin, "StakedToken2", "stkBT2");  
        
        vm.prank(admin);
        (bool sent, ) = proxyAddress.call(payload);  

        assert(sent == false);  //AlreadyInitialized()
    }

    function testCallStateVariable() public {

        // getIsCompounding
        bytes memory data = abi.encodeWithSignature("getIsAutoCompounding()");        
        (bool sent, bytes memory result) = proxyAddress.call(data);
        require(sent, 'call failed');
        
        //decode
        bool isAutoCompounding = abi.decode(result, (bool));
        assertEq(isAutoCompounding, false);
    }

    function testERC20() public {

        // name
        bytes memory data1 = abi.encodeWithSignature("name()");        
        (bool sent1, bytes memory result1) = proxyAddress.call(data1);
        require(sent1, 'call failed');    

        //decode
        string memory decoded1 = abi.decode(result1, (string));
        assertEq(decoded1, "stkMock");

        // symbol
        bytes memory data2 = abi.encodeWithSignature("symbol()");        
        (bool sent2, bytes memory result2) = proxyAddress.call(data2);
        require(sent2, 'call failed');    

        //decode
        string memory decoded2 = abi.decode(result2, (string));
        assertEq(decoded2, "stkM");
    }

    function testUserCannotCallSetUp() public {
        // admin
        bytes memory data = abi.encodeWithSignature("setUp(uint128,uint128,uint256,bool)", uint128(block.timestamp + 1), 30 seconds, 30 ether, true);        
        (bool sent, ) = proxyAddress.call(data);

        assertEq(sent, false);
    }
    
    function testAdminCanCallSetUp() public {
        
        assertEq(baseToken.balanceOf(vaultAddress), 30 * 30 ether);

        bytes memory data = abi.encodeWithSignature("setUp(uint128,uint128,uint256,bool)", uint128(block.timestamp + 1), 30 seconds, 30 ether, true);        

        vm.prank(admin);
        (bool sent, ) = proxyAddress.call(data);
        
        assertEq(sent, true);
    }

}

abstract contract StateSetUp is StateZero {
//Note: pool deployed, initialized and setUpured.

    function setUp() public virtual override {
        super.setUp();

        // call setUp
        assertEq(baseToken.balanceOf(vaultAddress), 30 * 30 ether);

        bytes memory data = abi.encodeWithSignature("setUp(uint128,uint128,uint256,bool)", uint128(block.timestamp + 1), 30 seconds, 30 ether, true);        

        vm.prank(admin);
        (bool sent, ) = proxyAddress.call(data);

        require(sent, "setUp failed");

        // fast forward to start
        vm.warp(block.timestamp + 1);
    }
}

contract StateSetUpTest is StateSetUp {

    function testCannotResetUpWhileActive() public {

        bytes memory data =  abi.encodeWithSignature("setUp(uint128,uint128,uint256,bool)", uint128(block.timestamp + 1), 20 seconds, 20 ether, true);      

        vm.prank(admin);
        (bool sent, ) = proxyAddress.call(data);

        assertEq(sent, false);  //"reward duration not finished"
    }

    function testDistributionEnd() public {
        
        bytes memory data = abi.encodeWithSignature("getDistributionEnd()");        
        (bool sent, bytes memory result) = proxyAddress.call(data);
        require(sent);

        //decode
        uint256 decoded = abi.decode(result, (uint256));

        assertEq(decoded, 32);
    }
    
    function testStake() public {
        vm.expectEmit(true,true,false,false);
        emit Staked(userA, userA, userABaseTokens);

        bytes memory data = abi.encodeWithSignature("stake(address,uint256)", userA, userABaseTokens); 

        vm.prank(userA);
        IStakingPool(proxyAddress).stake(userA, userABaseTokens);

        bytes memory data1 = abi.encodeWithSignature("balanceOf(address)", userA); 
        ( , bytes memory result) = proxyAddress.call(data1);

        //decode
        uint256 decoded = abi.decode(result, (uint256));

        assertEq(decoded, userABaseTokens); // equal amt of stkTokens
    }
}

abstract contract StateEnded is StateSetUp {
    function setUp() public virtual override {
        super.setUp();

        // userA stakes tokens
        vm.prank(userA);

        vm.expectEmit(true,true,false,false);
        emit Staked(userA, userA, userABaseTokens);

        bytes memory data = abi.encodeWithSignature("stake(address,uint256)", userA, userABaseTokens); 
        (bool sent, ) = proxyAddress.call(data);
        require(sent);

        // fast forward to end
        vm.warp(33);
    }
}

contract StateEndedTest is StateEnded {

        function testClaim() public {

        vm.expectEmit(true,true,false,false);
        emit RewardsClaimed(userA, userA, 30 ether);

        vm.prank(userA);
        bytes memory data = abi.encodeWithSignature("claim(address,uint256)", userA, type(uint256).max); 
        (bool sent, ) = proxyAddress.call(data);
        require(sent);

        // check base tokens received as rewards
        uint256 rewards = baseToken.balanceOf(userA);
        assertEq(rewards, 30 ether);

        // check stkTokens remain unburnt
        bytes memory data1 = abi.encodeWithSignature("balanceOf(address)", userA); 
        (bool sent1, bytes memory result) = proxyAddress.call(data1);
        require(sent1);

        //decode
        uint256 stkTokenBalance = abi.decode(result, (uint256));

        assertEq(stkTokenBalance, userABaseTokens); //1 ether of stkBT
    }


    function testUnstake() public {

        //testClaim();
        
        vm.expectEmit(true,true,false,false);
        emit Unstaked(userA, userA, userABaseTokens);

        vm.prank(userA);
        bytes memory data = abi.encodeWithSignature("unstake(address,uint256)", userA, type(uint256).max); 
        (bool sent, ) = proxyAddress.call(data);
        require(sent);

        assertEq(userABaseTokens, baseToken.balanceOf(userA));    
        
        // check stkTokens burnt
        bytes memory data1 = abi.encodeWithSignature("balanceOf(address)", userA); 
        ( , bytes memory result) = proxyAddress.call(data1);

        //decode
        uint256 stkTokenBalance = abi.decode(result, (uint256));
        assertEq(stkTokenBalance, 0);
    }
}

abstract contract StateUpgrade is StateEnded {
    
    function setUp() public virtual override {
        super.setUp();
    }

}

contract StateUpgradeTest is StateUpgrade {

    function testUserCannotUpgradeUUPS() public {
        StakingPoolIndex newStakingPool;

        vm.prank(admin);
        newStakingPool = new StakingPoolIndex();
        
        vm.expectRevert();
        vm.prank(userA);
        bytes memory data = abi.encodeWithSignature("upgradeToAndCall(address,bytes)", address(newStakingPool), ""); 
        (bool sent, ) = proxyAddress.call(data);
        require(sent);

        // proxy points to old implementation
        assertEq(proxy.implementation(), poolAddress);
    }

    function testadminCanUpgradeUUPS() public {
        StakingPoolIndex newStakingPool;

        vm.prank(admin);
        newStakingPool = new StakingPoolIndex();
        
        // check admin
        vm.prank(admin);
        bytes memory data = abi.encodeWithSignature("upgradeToAndCall(address,bytes)", address(newStakingPool), ""); 
        (bool sent, ) = proxyAddress.call(data);
        require(sent);

        // proxy points to new implementation
        assertEq(proxy.implementation(), address(newStakingPool));
    }


}