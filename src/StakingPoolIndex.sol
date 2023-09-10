// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import { StakingPoolStorage } from "./StakingPoolStorage.sol";
import { SafeERC20, IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

import { ERC20Upgradeable } from "openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import { PausableUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import { UUPSUpgradeable } from "openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";

/// @title A single-sided staking pool that is upgradeable
/// @author Calnix
/// @notice Stake TokenA, earn Token A as rewards
/// @dev Rewards are held in rewards vault, not in the staking pool. Necessary approvals are expected.
/// @dev Pool is only compatible with tokens of 18 dp precision.
contract StakingPoolIndex is
    ERC20Upgradeable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    StakingPoolStorage
{
    using SafeERC20 for IERC20;

    // version number
    uint256 public constant POOL_REVISION = 0x1;

    /**
     * @notice Initializes the Pool
     * @dev To be called by proxy on deployment
     * @param stakedToken Token accepted for staking
     * @param rewardToken Token emitted as rewards
     * @param rewardsVault Vault that holds rewards
     * @param owner Owner of staking pool
     * @param name ERC20 name of staked token (if receive TokenA for staking, mint stkTokenA to user)
     * @param symbol ERC20 symbol of staked token (if receive TokenA for staking, mint stkTokenA to user)
     */
    function initialize(IERC20 stakedToken, IERC20 rewardToken, address rewardsVault, address owner, string memory name, string memory symbol)
        external
        virtual
        initializer
    {
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
    function setUp(uint128 startTime, uint128 duration, uint256 amount, bool isAutoCompounding) virtual external onlyOwner {
        require(_isSetUp == false, "Already setUp");
        require(startTime > block.timestamp && duration > 0, "invalid params");

        _emissionPerSecond = uint128(amount / duration);

        //sanity checks
        require(_emissionPerSecond > 0, "reward rate = 0");
        require(_emissionPerSecond * duration <= REWARD_TOKEN.balanceOf(REWARDS_VAULT), "reward amount > balance");

        _startTime = startTime;
        _endTime = startTime + duration;

        if (isAutoCompounding) {
            _isAutoCompounding = isAutoCompounding;
            _assetIndex = 1e18;
        }
        
        _isSetUp = true;

        emit PoolInitiated(address(REWARD_TOKEN), isAutoCompounding, _emissionPerSecond);
    }

    /**
     * @notice Stake token to earn rewards. User stake on behalf of another address
     * @dev Users receive stkTokens on a 1:1 basis to the amount staked
     * @param onBehalfOf Address to stake under
     * @param amount Amount to stake
     */
    function stake(address onBehalfOf, uint256 amount) virtual external {
        require(block.timestamp >= _startTime, "Not started");
        require(amount > 0 && onBehalfOf > address(0), "Invalid params");

        uint256 unbookedRewards = _updateState(onBehalfOf, balanceOf(onBehalfOf), _isAutoCompounding);

        // book rewards accrued from lastUpdateTimestamp
        if (unbookedRewards > 0) {
            _accruedRewards[onBehalfOf] += unbookedRewards;
            emit RewardsAccrued(onBehalfOf, unbookedRewards);
        }

        // mint stkTokens
        _mint(onBehalfOf, amount);

        IERC20(STAKED_TOKEN).safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, onBehalfOf, amount);
    }

    /**
     * @notice Claim rewards earned. User can direct their redemption to an alternate address
     * @dev Ignores principal staked (If compounding enabled)
     * @param to Address to send rewards to
     * @param amount Amount of rewards to claim
     */
    function claim(address to, uint256 amount) virtual external {
        require(block.timestamp >= _startTime, "Not started");
        require(amount > 0 && to > address(0), "Invalid params");

        uint256 unbookedRewards = _updateState(msg.sender, balanceOf(msg.sender), _isAutoCompounding);

        uint256 totalUnclaimedRewards;
        if (unbookedRewards > 0) {
            totalUnclaimedRewards = _accruedRewards[to] += unbookedRewards;
            emit RewardsAccrued(msg.sender, unbookedRewards);
        }

        // non-zero total rewards
        if (totalUnclaimedRewards == 0) {
            revert("No rewards");
        }

        //rebase claim amount
        uint256 amountToClaim = amount > totalUnclaimedRewards ? totalUnclaimedRewards : amount;

        //update state
        _claimedRewards[msg.sender] += amountToClaim;
        _totalRewardsStaked -= amountToClaim;

        //transfer
        REWARD_TOKEN.safeTransferFrom(REWARDS_VAULT, to, amountToClaim);

        emit RewardsClaimed(msg.sender, to, amountToClaim);
    }

    /**
     * @notice Unstake principally staked tokens. User can direct their redemption to an alternate address
     * @dev Unstake only applies to staked principal
     * @param to Address to redeem to
     * @param amount Amount to redeem
     */
    function unstake(address to, uint256 amount) virtual external {
        require(block.timestamp >= _startTime, "Not started");
        require(amount > 0 && to > address(0), "Invalid params");

        //get user's principle balance of staked tokens
        uint256 userPrincipleBalance = balanceOf(msg.sender);
        if (userPrincipleBalance == 0) {
            revert("Nothing staked");
        }

        // account for unbooked rewards
        uint256 unbookedRewards = _updateState(msg.sender, userPrincipleBalance, _isAutoCompounding);

        if (unbookedRewards > 0) {
            _accruedRewards[msg.sender] += unbookedRewards;
            emit RewardsAccrued(msg.sender, unbookedRewards);
        }

        //rebase amount
        uint256 amountToRedeem = amount > userPrincipleBalance ? userPrincipleBalance : amount;

        // burn & transfer
        _burn(msg.sender, amountToRedeem);
        IERC20(STAKED_TOKEN).safeTransfer(to, amountToRedeem);

        emit Unstaked(msg.sender, to, amountToRedeem);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Calculates user's unbooked rewards depending if compounding is enabled
     * @param user Address to calcuate for
     * @param userPrincipleBalance User's staked tokens (ignoring accrued rewards)
     * @return unbookedRewards from userIndex till current assetIndex
     */
    function _updateState(address user, uint256 userPrincipleBalance, bool isAutoCompounding) internal returns (uint256) {
        uint256 unbookedRewards;

        if (isAutoCompounding) {   // Emitted rewards split based on principle staked and rewards accrued thus far.

            uint256 totalStaked = totalSupply() + _totalRewardsStaked;

            //user's unbooked rewards: totalStaked must include rewards in compounding
            unbookedRewards = _updateUserIndex(user, userPrincipleBalance, totalStaked);

        } else {    //Linear: No compounding

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
    function _updateUserIndex(address user, uint256 stakedByUser, uint256 totalStaked) internal returns (uint256) {
        uint256 userIndex = _userIndexes[user];
        uint256 accruedRewards;

        //get latest assetIndex
        uint256 newAssetIndex = _updateAssetIndex(totalStaked);

        //update user index + calculate unbooked rewards
        if (userIndex != newAssetIndex) {
            if (stakedByUser > 0) {
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
    function _updateAssetIndex(uint256 totalStaked) internal returns (uint256) {
        uint256 oldAssetIndex = _assetIndex;

        if (block.timestamp == _lastUpdateTimestamp) {
            return oldAssetIndex;
        }

        (uint256 newAssetIndex, uint256 rewardsEmittedSinceUpdate) = _calculateAssetIndex(
            oldAssetIndex, _emissionPerSecond, _lastUpdateTimestamp, totalStaked, _isAutoCompounding
        );

        if (newAssetIndex != oldAssetIndex) {
            _assetIndex = newAssetIndex;

            if (_isAutoCompounding) {
                _totalRewardsStaked += rewardsEmittedSinceUpdate;
            }

            emit AssetIndexUpdated(address(REWARD_TOKEN), oldAssetIndex, newAssetIndex);
        }

        _lastUpdateTimestamp = uint128(block.timestamp);

        return newAssetIndex;
    }

    /**
     * @dev Calculates latest asset index, reflective of emissions thus far
     * @param currentAssetIndex Latest asset index
     * @param emissionPerSecond Reward tokens emitted per second (in wei)
     * @param lastUpdateTimestamp Time at which previous update occured
     * @param totalBalance Total staked supply
     * @return newassetIndex Latest asset index
     */
    function _calculateAssetIndex(uint256 currentAssetIndex, uint256 emissionPerSecond, uint128 lastUpdateTimestamp, uint256 totalBalance, bool isAutoCompounding) internal view returns (uint256, uint256) {
        if (
            emissionPerSecond == 0                      // 0 emissions. setup() not executed.
            || totalBalance == 0                        // nothing has been staked
            || lastUpdateTimestamp == block.timestamp   // assetIndex already updated
            || lastUpdateTimestamp >= _endTime          // distribution has ended
        ) {
            return (currentAssetIndex, 0);
        }

        uint256 currentTimestamp = block.timestamp > _endTime ? _endTime : block.timestamp;
        uint256 timeDelta = currentTimestamp - lastUpdateTimestamp;

        uint256 nextAssetIndex;
        if (isAutoCompounding) {
            uint256 rewardsEmittedSinceUpdate = emissionPerSecond * timeDelta;

            uint256 emissionPerShareForPeriod = emissionPerSecond * timeDelta * 10 ** PRECISION / totalBalance;
            nextAssetIndex = (emissionPerShareForPeriod + 1e18) * currentAssetIndex / 10 ** PRECISION;

            return (nextAssetIndex, rewardsEmittedSinceUpdate);

        } else {

            nextAssetIndex = ((emissionPerSecond * timeDelta * 10 ** PRECISION) / totalBalance) + currentAssetIndex;
            return (nextAssetIndex, 0);
        }
    }

    /**
     * @dev Calculates user's accrued rewards from user index to specified asset index
     * @param principalUserBalance User's staked balance (includes rewards if compounding is enabled)
     * @param assetIndex Latest asset index, reflective of current conditions
     * @param userIndex User's last updated index
     */
    function _calculateRewards(uint256 principalUserBalance, uint256 assetIndex, uint256 userIndex) internal view returns (uint256) {
        if (_isAutoCompounding) {
            
            // CI = P[(1 + i)**n - 1]
            return (principalUserBalance * ((assetIndex * 10 ** PRECISION / userIndex) - 1e18)) / 10 ** PRECISION;

        } else {
            return (principalUserBalance * (assetIndex - userIndex)) / 10 ** PRECISION;
        }
    }

    /*//////////////////////////////////////////////////////////////
                           OVERRIDE TRANSFERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev When user staked Token to receive stkToken, the stkToken is non-transferable.
     * @dev This function is override to prevent transfer.
     * @param from Address to transfer from
     * @param to Address to transfer to
     * @param value Amount to transfer
     */
    function transferFrom(address from, address to, uint256 value) public override returns (bool) {
        revert("Staked token is not transferable");
    }

    /**
     * @dev When user staked Token to receive stkToken, the stkToken is non-transferable.
     * @dev This function is override to prevent transfer.
     * @param to Address to transfer to
     * @param value Amount to transfer
     */
    function transfer(address to, uint256 value) public override returns (bool) {
        revert("Staked token is not transferable");
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    function getassetIndex() external view returns (uint256) {
        return _assetIndex;
    }

    function getEmissionPerSecond() external view returns (uint128) {
        return _emissionPerSecond;
    }

    function getLastUpdateTimestamp() external view returns (uint128) {
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

    function getTotalRewardsStaked() external view returns (uint256) {
        return _totalRewardsStaked;
    }

    function getUserIndex(address user) external view returns (uint256) {
        return _userIndexes[user];
    }

    function getUserRewards(address user) external view returns (uint256) {
        
        // get necessary params
        uint256 totalStaked;
        if(_isAutoCompounding){
            totalStaked = totalSupply() + _totalRewardsStaked;
        } else {
            totalStaked = totalSupply();
        }
        
        // calculate latest index
        (uint256 newAssetIndex, ) = _calculateAssetIndex(_assetIndex, _emissionPerSecond, _lastUpdateTimestamp, totalStaked, _isAutoCompounding);

        // calculate user rewards
        uint256 stakedByUser = balanceOf(user);
        uint256 userIndex = _userIndexes[user];
        uint256 userRewards = _accruedRewards[user] + _calculateRewards(stakedByUser, newAssetIndex, userIndex);
        
        return userRewards;
    }

    function getClaimedRewards(address user) external view returns (uint256) {
        return _claimedRewards[user];
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
