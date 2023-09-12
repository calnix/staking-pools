// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { ERC20Mock } from "openzeppelin-contracts/contracts/mocks/token/ERC20Mock.sol";
import { Ownable } from "openzeppelin-contracts/contracts/access/Ownable.sol";
import { SafeERC20, IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { StakingPoolIndex } from "./StakingPoolIndex.sol";
import { StakingPoolProxy } from "./StakingPoolProxy.sol";
import { RewardsVault } from "./RewardsVault.sol";

/// @title Simple factory contract for create2 deployment of pool and supporting contracts
/// @author Calnix
/// @dev Pool used here is the StakingPoolIndex
/// @notice This is a simple cut-down version for illustration, not meant for production.

contract Factory is Ownable {
    using SafeERC20 for IERC20;

    struct Batch {
        StakingPoolIndex pool;
        StakingPoolProxy proxy;
        RewardsVault vault;
    }

    // tracks deployments
    mapping(uint256 index => Batch batch) public deployments;

    // counter
    uint256 public index;

    // events
    event Deployed(address indexed pool, address indexed proxy, address indexed vault);

    constructor(address admin) Ownable(admin) {}

    /*//////////////////////////////////////////////////////////////
                                 DEPLOY
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Deploys batch
     * @param salt Random number of choice
     */
    function deploy(IERC20 stakedToken, IERC20 rewardToken, address moneyManager, address admin, string memory name, string memory symbol, uint256 salt) external onlyOwner returns (address, address, address) {
        StakingPoolIndex pool = new StakingPoolIndex{salt: bytes32(salt)}();

        RewardsVault vault = new RewardsVault{salt: bytes32(salt)}(rewardToken, moneyManager, admin);

        bytes memory payload = abi.encodeWithSignature("initialize(address,address,address,address,string,string)", stakedToken, rewardToken, address(vault), admin, name, symbol);

        StakingPoolProxy proxy = new StakingPoolProxy{salt: bytes32(salt)}(address(pool), payload);

        // update mapping + index
        Batch memory batch = Batch({ pool: pool, proxy: proxy, vault: vault });

        deployments[index] = batch;
        index++;

        emit Deployed(address(pool), address(proxy), address(vault));

        return (address(pool), address(proxy), address(vault));
    }

    /**
     * @dev Get address of contract to be deployed
     * @param bytecode Bytecode of the contract to be deployed (include constructor params)
     * @param salt Random number of choice
     */
    function getAddress(bytes memory bytecode, uint256 salt) public view returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode)));

        // cast last 20 bytes of hash to address
        return address(uint160(uint256(hash)));
    }

    /**
     * @dev Precompute address of pool contract
     * @return poolAddress Address of pool
     */
    function precomputePoolAddress(uint256 salt) public view returns (address) {
        bytes memory bytecode = type(StakingPoolIndex).creationCode;

        //append constructor arguments
        bytes memory appendedBytecode = abi.encodePacked(bytecode);

        address poolAddress = getAddress(appendedBytecode, salt);
        return poolAddress;
    }

    /**
     * @dev Precompute address of proxy contract
     * @return proxyAddress Address of proxy
     */
    function precomputeProxyAddress(IERC20 stakedToken, IERC20 rewardToken, address vault, address poolAddress, address admin, string memory name, string memory symbol, uint256 salt) public view returns (address) {
        bytes memory bytecode = type(StakingPoolProxy).creationCode;

        //append constructor arguments
        bytes memory payload = abi.encodeWithSignature("initialize(address,address,address,address,string,string)", stakedToken, rewardToken, vault, admin, name, symbol);

        bytes memory appendedBytecode = abi.encodePacked(bytecode, abi.encode(poolAddress, payload));

        address proxyAddress = getAddress(appendedBytecode, salt);
        return proxyAddress;
    }

    /**
     * @dev Precompute address of vault contract
     * @return vaultAddress Address of vault
     */
    function precomputeVaultByteCode(IERC20 rewardToken, address moneyManager, address admin, uint256 salt) public view returns (address) {
        bytes memory bytecode = type(RewardsVault).creationCode;

        //append constructor arguments
        bytes memory appendedBytecode = abi.encodePacked(bytecode, abi.encode(rewardToken, moneyManager, admin));

        address vaultAddress = getAddress(appendedBytecode, salt);
        return vaultAddress;
    }
}
