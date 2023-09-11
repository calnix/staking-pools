// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { PausableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import { UUPSUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";


// Note: WIP - Compounding mode works. Working on linear mode.

contract StakingPoolShares is OwnableUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    using SafeERC20 for IERC20;

    IERC20 internal token;
    address internal vault;

    struct UserInfo {
        uint256 principle;      //denoted in asset
        uint256 shares;         //total shares
        uint256 UserlastUpdateTimestamp;
    }

    mapping(address user => UserInfo userInfo) internal _users;

    uint256 internal _totalStaked;                 
    uint256 internal _totalShares;
    
    uint256 internal _totalRewards;              //increments from first stake; accounts for rewards to users.
    uint256 internal _totalRewardsHarvested;     //increments from start time
    
    // Distribution info
    uint256 internal _startTime;                //for set&forget
    uint256 internal _endTime;
    uint256 internal _lastUpdateTimestamp;           //for calculating pendings rewards
    uint256 internal _emissionPerSecond;
    bool internal _isAutoCompounding;
    bool internal _isSetUp;

    // EVENTS
    event PoolInitiated(address indexed rewardToken, bool isCompounding, uint256 emission);
    event Staked(address indexed from, address indexed onBehalfOf, uint256 amount);
    event Unstaked(address indexed from, address indexed to, uint256 amount);
    
    event RewardsHarvested(address indexed rewardToken, uint256 amount);
    event RewardsClaimed(address indexed from, address indexed to, uint256 amount);

    event Recovered(address indexed token, uint256 amount);

    /**
     * @notice Initializes the Pool
     * @dev To be called by proxy on deployment
     * @param stakedToken Token accepted for staking
     * @param rewardsVault Vault that holds rewards
     * @param owner Owner of staking pool
     */
    function initialize(IERC20 stakedToken, address rewardsVault, address owner) external virtual initializer {
        token = stakedToken;
        vault = rewardsVault;

        __Ownable_init(owner);
        __UUPSUpgradeable_init();
    }


    function setUp(uint256 startTime, uint256 duration, uint256 amount, bool isAutoCompounding) external onlyOwner {
        require(_isSetUp == false, "Already setUp");
        require(startTime > block.timestamp && duration > 0, "invalid params");

        _emissionPerSecond = amount / duration;

        //sanity checks
        require(_emissionPerSecond > 0, "reward rate = 0");
        require(_emissionPerSecond * duration <= token.balanceOf(vault), "insufficient rewards");

        _startTime = _lastUpdateTimestamp = startTime;
        _endTime = startTime + duration;

        _isAutoCompounding = isAutoCompounding;

        _isSetUp = true;

        emit PoolInitiated(vault, isAutoCompounding, _emissionPerSecond);
    }

    function stake(address onBehalfOf, uint256 amount) external {
        require(block.timestamp >= _startTime, "Not started");
        require(amount > 0 && onBehalfOf > address(0), "Invalid params");

        UserInfo memory user = _users[onBehalfOf];

        //get rewards from vault
        //should only run once, per block
        _harvest();  

        //calculate new shares
        uint256 newShares;
        if(_isAutoCompounding){

            if (_totalShares > 0) {
                newShares = (amount * _totalShares) / (_totalRewards + _totalStaked);
            } else {
                newShares = amount; //1:1 ratio initally
            }

        } else {  //linear
            newShares = amount;
        } 

        //update memory
        user.principle += amount;
        user.shares += newShares;

        //update storage
        _users[onBehalfOf] = user;
        _totalShares += newShares;
        _totalStaked += amount;

        // get staking tokens
        token.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, onBehalfOf, amount);
    }

    function claim(address to, uint256 amount) external {
        require(block.timestamp >= _startTime, "Not started");
        require(amount > 0 && to > address(0), "Invalid params");

        UserInfo memory user = _users[msg.sender];

        // get pending + update state
        _harvest();

        uint256 userTotalAssets;
        uint256 userTotalRewards;

        if(_isAutoCompounding){
            // userTotalPosition = principle + rewards
            userTotalAssets = (user.shares * (_totalRewards + _totalStaked)) / _totalShares;
            // remove principal
            userTotalRewards = userTotalAssets - user.principle;

        }else{
            // linear: shares == principle
            userTotalRewards = user.shares * _totalRewards / _totalShares;
        }

        // non-zero rewards
        if (userTotalRewards == 0) {
            revert("No rewards");
        }
        
        //rebase claim amount
        uint256 amountToClaim = amount > userTotalRewards ? userTotalRewards : amount;

        //number of shares
        uint256 amountInShares = amountToClaim * _totalShares / (_totalRewards + _totalStaked);

        //update memory
        user.shares -= amountInShares;

        //update storage
        _totalRewards -= amountToClaim;
        _totalShares -= amountInShares;
        _users[msg.sender] = user;

        // get staking tokens
        token.safeTransfer(msg.sender, amountToClaim);

        emit RewardsClaimed(msg.sender, to, amountToClaim);
    }

    // user specifies principle as amount, not shares; user should not need to do math.
    function unstake(address onBehalfOf, uint256 amount) external {
        require(block.timestamp >= _startTime, "Not started");
        require(amount > 0 && onBehalfOf > address(0), "Invalid params");

        // copy to memory
        UserInfo memory user = _users[msg.sender]; 
        
        uint256 amountToUnstake = amount > user.principle ? user.principle : amount;

        //in shares
        uint256 amountInShares;
        if(_totalShares > 0){
            amountInShares = amountToUnstake * _totalShares / (_totalRewards + _totalStaked);

        }else{
            amountInShares = amountToUnstake;
        }

        // update
        user.shares -= amountInShares;
        user.principle -= amountToUnstake;

        //update storage
        _users[msg.sender] = user;
        _totalStaked -= amountToUnstake;
        _totalShares -= amountInShares;
        
        //transfer
        token.safeTransfer(onBehalfOf, amountToUnstake);

        emit Unstaked(msg.sender, onBehalfOf, amountToUnstake);
    }

    function _harvest() internal {

        // 2 txns in the same block -> same block.timestamp
        if (block.timestamp > _lastUpdateTimestamp) {

            uint256 currentTime = block.timestamp > _endTime ? _endTime : block.timestamp;
            uint256 rewardsEmitted = (currentTime - _lastUpdateTimestamp) * _emissionPerSecond;

            // update storage
            _totalRewardsHarvested += rewardsEmitted;
            if (_totalShares > 0) {
                _totalRewards += rewardsEmitted; // so that on first deposit, there are no rewards, inflating ex.rate
                    
            }

            //update time
            _lastUpdateTimestamp = block.timestamp;
            
            //transfer
            token.safeTransferFrom(vault, address(this), rewardsEmitted);

            emit RewardsHarvested(address(token), rewardsEmitted);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    function getUserPrinciple(address user) external view returns (uint256) {
        return _users[user].principle; 
    }

    function getUserShares(address user) external view returns (uint256) {
        return _users[user].shares; 
    }

    function getUserRewards(address user) external view returns (uint256) {
        uint256 currentTime = block.timestamp > _endTime ? _endTime : block.timestamp;

        uint256 timeDelta = currentTime - _lastUpdateTimestamp;   
        uint256 pendingHarvestRewards = _emissionPerSecond * timeDelta;

        uint256 currentTotalRewards = _totalRewards + pendingHarvestRewards;

        uint256 userAssets = _users[user].shares * (currentTotalRewards + _totalStaked) / _totalShares;
        return userAssets - _users[user].principle; 
    }

    function getTotalStaked() external view returns(uint256){
        return _totalStaked;
    }

    function getTotalShares() external view returns(uint256){
        return _totalShares;
    }

    function getTotalRewards() external view returns(uint256){
        return _totalRewards;
    }

    function getTotalRewardsHarvested() external view returns(uint256){
        return _totalRewardsHarvested;
    }

    function getEmissionPerSecond() external view returns (uint256) {
        return _emissionPerSecond;
    }

    function getLastUpdateTimestamp() external view returns (uint256) {
        return _lastUpdateTimestamp;
    }

    function getDistributionStart() external view returns (uint256) {
        return _startTime;
    }

    function getDistributionEnd() external view returns (uint256) {
        return _endTime;
    }

    function getIsAutoCompounding() external view returns (bool) {
        return _isAutoCompounding;
    }

    /*//////////////////////////////////////////////////////////////
                             UPGRADEABILITY
    //////////////////////////////////////////////////////////////*/

    ///@dev override _authorizeUpgrade with onlyOwner for UUPS compliant implementation
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner { }

    /*//////////////////////////////////////////////////////////////
                                RECOVER
    //////////////////////////////////////////////////////////////*/

    function recoverERC20(address tokenAddress, uint256 amount) external onlyOwner {
        IERC20(tokenAddress).safeTransfer(owner(), amount);
        emit Recovered(tokenAddress, amount);
    }
}
