// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {StakingPoolStorage} from "./StakingPoolStorage.sol";
import {SafeERC20, IERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import {ERC20Upgradeable} from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {OwnableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

/// @title A single-sided staking pool that is upgradeable
/// @author Calnix
/// @notice Stake TokenA, earn Token A as rewards
/// @dev Rewards are held in rewards vault, not in the staking pool. Necessary approvals are expected.
/// @dev Pool is only compatible with tokens of 18 dp precision.
contract AutoPool is ERC20Upgradeable, OwnableUpgradeable, PausableUpgradeable, UUPSUpgradeable, StakingPoolStorage {
    using SafeERC20 for IERC20;

    // version number
    uint256 public constant POOL_REVISION = 0x1;

    /**
     * @notice Initializes the Pool
     * @dev To be called by proxy on deployment
     * @param stakedToken Token accepted for staking
     * @param rewardToken Token emitted as rewards
     * @param rewardsVault Vault that holds rewards
     * @param name ERC20 name of staked token (if receive TokenA for staking, mint stkTokenA to user)
     * @param symbol ERC20 symbol of staked token (if receive TokenA for staking, mint stkTokenA to user)
     */
    function initialize(IERC20 stakedToken, IERC20 rewardToken, address rewardsVault, address owner, string memory name, string memory symbol) 
        external virtual initializer {
            STAKED_TOKEN = stakedToken;
            REWARD_TOKEN = rewardToken;
            REWARDS_VAULT = rewardsVault;

            __ERC20_init(name, symbol);
            __Ownable_init(owner);
            __UUPSUpgradeable_init();
    }
    
    /*//////////////////////////////////////////////////////////////
                                EXTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Configures the staking program
     * @dev Ensure sufficient rewards are in the vault beforehand, else will revert
     * @param duration Period for which rewards are emitted (in seconds)
     * @param amount Amount of tokens in wei (18 dp precision) 
     * @param isAutoCompounding If true, enable compounding
     */
    function setUp(uint256 duration, uint256 amount, bool isAutoCompounding) external onlyOwner {
        //require(_endTime < block.timestamp, "on-going distribution");

        _emissionPerSecond = uint128(amount / duration);  
        
        //sanity checks
        require(_emissionPerSecond > 0, "reward rate = 0");
        require(_emissionPerSecond * duration <= REWARD_TOKEN.balanceOf(REWARDS_VAULT), "reward amount > balance");

        _startTime = _lastUpdateTimestamp = uint128(block.timestamp);
        _endTime = uint128(block.timestamp) + uint128(duration);  

        if(isAutoCompounding){
            _isAutoCompounding = isAutoCompounding;
            _assetIndex = 1e18;
        }

        emit PoolInitiated(address(REWARD_TOKEN), isAutoCompounding, _emissionPerSecond);
    }

    /**
     * @notice Stake token to earn rewards. User stake on behalf of another address
     * @dev Users receive stkTokens on a 1:1 basis to the amount staked
     * @param user Address to stake under
     * @param amount Amount to stake
     */
    function stake(address user, uint256 amount) external {
        require(amount > 0, "Invalid amount");
        require(user > address(0), "Invalid address");
        
        uint256 unbookedRewards = _updateState(user, balanceOf(user));

        // book previously accrued rewards
        if (unbookedRewards > 0) {

            _accruedRewards[user] += unbookedRewards;
            //_totalRewardsStaked += unbookedRewards;

            emit RewardsAccrued(user, unbookedRewards);
        }

        // mint stkTokens
        _mint(user, amount);
        
        IERC20(STAKED_TOKEN).safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, user, amount);
    }

    /**
     * @notice Claim rewards earned. User can direct their redemption to an alternate address
     * @dev Ignores principal staked (If compounding enabled)
     * @param to Address to send rewards to
     * @param amount Amount of rewards to claim
     */
    function claim(address to, uint256 amount) external {
        require(amount > 0, "Invalid amount");
        require(to > address(0), "Invalid address");

        uint256 unbookedRewards = _updateState(msg.sender, balanceOf(msg.sender));
        // total rewards
        uint256 totalUnclaimedRewards = _accruedRewards[msg.sender] + unbookedRewards;
        require(totalUnclaimedRewards > 0, "No rewards");

        if (unbookedRewards > 0){
            emit RewardsAccrued(msg.sender, unbookedRewards);
        }

        //rebase claim amount
        uint256 amountToClaim = amount > totalUnclaimedRewards ? totalUnclaimedRewards : amount;

        //update state
        _accruedRewards[msg.sender] = totalUnclaimedRewards - amountToClaim;
        _claimedRewards[msg.sender] += amountToClaim;

        if(amountToClaim < unbookedRewards) {
            
            // increase total by leftover unbooked rewards from user
            //_totalRewardsStaked += unbookedRewards - amountToClaim;
            _totalRewardsStaked -= amountToClaim;

        } else{ //unbookedRewards < amountToClaim

            //_totalRewardsStaked -= amountToClaim - unbookedRewards;
            _totalRewardsStaked -= amountToClaim;

        }

        REWARD_TOKEN.safeTransferFrom(REWARDS_VAULT, to, amountToClaim);

        emit RewardsClaimed(msg.sender, to, amountToClaim);
    }

    /** 
     * @notice Unstake principally staked tokens. User can direct their redemption to an alternate address
     * @dev Unstake only applies to staked principal
     * @param to Address to redeem to
     * @param amount Amount to redeem
     */
    function unstake(address to, uint256 amount) external {
        require(amount > 0, "Invalid amount");
        require(to > address(0), "Invalid address");

        //get user's principle balance of staked tokens
        uint256 userPrincipleBalance = balanceOf(msg.sender);
        require(userPrincipleBalance > 0, "Nothing staked"); 

        //rebase amount
        uint256 amountToRedeem = amount > userPrincipleBalance ? userPrincipleBalance : amount;
        // account for unbooked rewards
        uint256 unbookedRewards = _updateState(msg.sender, userPrincipleBalance);

        if (unbookedRewards > 0) {

            _accruedRewards[msg.sender] += unbookedRewards;
            _totalRewardsStaked += unbookedRewards;

            emit RewardsAccrued(msg.sender, unbookedRewards);
        }

        _burn(msg.sender, amountToRedeem);

        IERC20(STAKED_TOKEN).safeTransfer(to, amountToRedeem);

        emit Unstaked(msg.sender, to, amountToRedeem);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _getRewardsEmittedSinceUpdate() internal returns(uint256){
        require(block.timestamp >= _startTime, "not started");

        uint256 currentTimestamp = block.timestamp > _endTime ? _endTime : block.timestamp;

        return (currentTimestamp - _lastUpdateTimestamp) * _emissionPerSecond;
    }

    /// @dev Calculates user's unbooked rewards depending if compounding is enabled
    /// @param user Address to calcuate for 
    /// @param userPrincipleBalance User's staked tokens (ignoring accrued rewards)
    /// @return unbookedRewards from userIndex till current assetIndex
    function _updateState(address user, uint256 userPrincipleBalance) internal returns(uint256) {
        uint256 unbookedRewards;

        if (_isAutoCompounding) { // Rewards emitted based on principle staked amount and rewards accrued thus far.

            uint256 totalStaked = totalSupply() + _totalRewardsStaked;

            //user's unbooked rewards
            unbookedRewards = _updateUserIndex(user, userPrincipleBalance, totalStaked);
        
        } else { // Rewards emitted based on principle staked amount; rewards accrued are ignored.

            //user's unbooked rewards
            unbookedRewards = _updateUserIndex(user, userPrincipleBalance, totalSupply());
        }

        return unbookedRewards;
    }

    /**
     * @dev Calculates user's unbooked rewards depending on which mode pool is set to 
     * @param user Address to calcuate for 
     * @param stakedByUser User's staked balance
     * @param totalStaked Total staked supply 
     * @return _accruedRewards Unbooked rewards from userIndex till current assetIndex
     */
    function _updateUserIndex(address user, uint256 stakedByUser, uint256 totalStaked) internal returns(uint256) {
        uint256 userIndex = _userIndexes[user];
        uint256 accruedRewards;

        //get latest assetIndex
        uint256 newAssetIndex = _updateAssetIndex(totalStaked); 
        
        //update user index + calculate unbooked rewards
        if(userIndex != newAssetIndex) {
            if(stakedByUser > 0) {
                accruedRewards = _calculateRewards(stakedByUser, newAssetIndex, userIndex);
            }

            _userIndexes[user] = newAssetIndex;
            emit UserIndexUpdated(user, newAssetIndex);
        }

        return accruedRewards;
    }

    /**
     * @dev Check if asset index is in need of updating to bring it in-line to present conditions
     * @param totalStaked Total staked supply at lastUpdateTimestamp
     * @return newAssetIndex Latest asset index
     */
    function _updateAssetIndex(uint256 totalStaked) internal returns(uint256) {
        uint256 oldAssetIndex = _assetIndex; 
        
        if (block.timestamp == _lastUpdateTimestamp) {
            return oldAssetIndex;
        }
        
        //totalStaked must include rewards in compounding
        uint256 newAssetIndex = _calculateAssetIndex(oldAssetIndex, _emissionPerSecond, _lastUpdateTimestamp, totalStaked); 

        if (newAssetIndex != oldAssetIndex) {
            _assetIndex = newAssetIndex;
            emit AssetIndexUpdated(address(REWARD_TOKEN), newAssetIndex);
        }

        _lastUpdateTimestamp = uint128(block.timestamp);

        return newAssetIndex;
    }

    /**
     * @dev Calculates latest asset index, reflective of emissions thus far
     * @param currentAssetIndex Latest asset index
     * @param _emissionPerSecond Reward tokens emitted per second (in wei)
     * @param _lastUpdateTimestamp Time at which previous update occured 
     * @param totalBalance Total staked supply 
     * @return newassetIndex Latest asset index
     */
    function _calculateAssetIndex(uint256 currentAssetIndex, uint256 _emissionPerSecond, uint128 _lastUpdateTimestamp, uint256 totalBalance) public returns(uint256) {

        if(
            _emissionPerSecond == 0 ||                        // 0 emissions. setup() not executed. 
            totalBalance == 0 ||                             // nothing has been staked 
            _lastUpdateTimestamp == block.timestamp ||        // assetIndex already updated 
            _lastUpdateTimestamp >= _endTime                  // distribution has ended
        ) {
            return currentAssetIndex;
        }

        uint256 currentTimestamp = block.timestamp > _endTime ? _endTime : block.timestamp;
        uint256 timeDelta = currentTimestamp - _lastUpdateTimestamp;

        if(_isAutoCompounding){
            
            _totalRewardsStaked += _emissionPerSecond * timeDelta;

            return (_emissionPerSecond * timeDelta * currentAssetIndex) / totalBalance; ///@audit precision
            
        }else{
            return ((_emissionPerSecond * timeDelta * 10**PRECISION) / totalBalance) + currentAssetIndex;
        }

    }

    /**
     * @dev Calculates user's accrued rewards from user index to specified asset index
     * @param principalUserBalance User's staked balance (includes rewards if compounding is enabled)
     * @param assetIndex Latest asset index, reflective of current conditions
     * @param userIndex User's last updated index
     */
    function _calculateRewards(uint256 principalUserBalance, uint256 assetIndex, uint256 userIndex) internal view returns(uint256){
        
        if(_isAutoCompounding){

            return (principalUserBalance * assetIndex) / userIndex;     ///@audit precision

        } else{

            return (principalUserBalance * (assetIndex - userIndex)) / 10**PRECISION;
        }
    }

    /*//////////////////////////////////////////////////////////////
                           OVERRIDE TRANSFERS
    //////////////////////////////////////////////////////////////*/

    /// @dev When user staked Token to receive stkToken, the stkToken is non-transferable.
    /// @dev This function is override to prevent transfer.
    /// @param from Address to transfer from
    /// @param to Address to transfer to
    /// @param value Amount to transfer
    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        revert("Staked token is not transferable");
    }

    
    /// @dev When user staked Token to receive stkToken, the stkToken is non-transferable.
    /// @dev This function is override to prevent transfer.
    /// @param to Address to transfer to
    /// @param value Amount to transfer
    function transfer(address to, uint256 value) public override returns (bool) {
        revert("Staked token is not transferable");
    }


    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    function getassetIndex() external view returns(uint256) {
        return _assetIndex;
    }

    function getEmissionPerSecond() external view returns(uint128) {
        return _emissionPerSecond;
    }

    function getLastUpdateTimestamp() external view returns(uint128) {
        return _lastUpdateTimestamp;
    }

    function getDistributionEnd() external view returns(uint256) {
        return _endTime;
    }

    function getIsAutoCompounding() external view returns(bool) {
        return _isAutoCompounding;
    }
    
    function getTotalRewardsStaked() external view returns(uint256) {
        return _totalRewardsStaked;
    }

    function getUserIndex(address user) external view returns(uint256) {
        return _userIndexes[user];
    }

    function getBookedRewards(address user) external view returns(uint256) {
        return _accruedRewards[user];
    }

    function getClaimedRewards(address user) external view returns(uint256) {
        return _claimedRewards[user];
    }

    /*//////////////////////////////////////////////////////////////
                             UPGRADEABILITY
    //////////////////////////////////////////////////////////////*/

    ///@dev override _authorizeUpgrade with onlyOwner for UUPS compliant implementation
    function _authorizeUpgrade(address newImplementation) internal onlyOwner override {}
    
    
    /*//////////////////////////////////////////////////////////////
                                RECOVER
    //////////////////////////////////////////////////////////////*/
    
    function recoverERC20(address tokenAddress, uint256 amount) external onlyOwner {
        IERC20(tokenAddress).safeTransfer(owner(), amount);
        emit Recovered(tokenAddress, amount);
    }

}