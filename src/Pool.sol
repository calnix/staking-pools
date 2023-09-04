// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract Foo {
    using SafeERC20 for IERC20;

    IERC20 internal token;
    address internal vault;

    struct UserInfo {
        uint256 principle; //denoted in asset
        uint256 shares; //total shares
            //uint256 lastUserActionTime;
    }

    mapping(address user => UserInfo userInfo) internal _users;

    uint256 internal _totalShares;
    uint256 internal _totalRewards;              //increments from first deposit. accounts for rewards to users.
    uint256 internal _totalRewardsHarvested;     //always incremented: final value should reflect total emitted
    
    
    //Asset Index
    uint256 internal _emissionPerSecond;
    uint256 internal _lastUpdateTime; //for calculating pendings rewards

    uint256 internal _totalStaked; // only principal staked
    uint256 internal _startTime; // for set&forget
    uint256 internal _endTime;

    // EVENTS
    event RewardsHarvested(address indexed token, uint256 amount);
    event Staked(address indexed from, address indexed onBehalfOf, uint256 amount);
    event RewardsClaimed(address indexed from, address indexed to, uint256 amount);
    event Redeem(address indexed from, address indexed to, uint256 amount);

    function setUp(uint256 startTime, uint256 duration, uint256 amount) external {
        //onlyOwner
        require(_endTime < block.timestamp, "on-going distribution");

        _startTime = startTime;
        _endTime = startTime + duration;

        _emissionPerSecond = amount / duration; //duration in seconds

        //sanity checks
        require(_emissionPerSecond > 0, "reward rate = 0");
        require(_emissionPerSecond * duration <= token.balanceOf(vault), "insufficient rewards");

        //_isAutoCompounding = isAutoCompounding;
    }

    function stake(address onBehalfOf, uint256 amount) external {
        require(block.timestamp > _startTime, "Not started");
        require(amount > 0 && onBehalfOf > address(0), "Invalid params");

        UserInfo storage user = _users[onBehalfOf]; //storage or mem?

        //get rewards from vault
        //should only run once, per block
        _harvest();

        // handle emitted unclaimed rewards
        // must remove to avoid inflation on first deposit
        // this will run once, one the first deposit

        //calculate new shares
        uint256 newShares;
        if (_totalShares > 0) {
            newShares = (amount * _totalShares) / _totalRewards;
        } else {
            newShares = amount; //1:1 ratio initally
        }

        //update storage
        user.principle += amount;
        user.shares += newShares;
        _totalShares += newShares;

        // get staking tokens
        token.safeTransferFrom(msg.sender, address(this), amount);

        emit Staked(msg.sender, onBehalfOf, amount);
    }

    function claimRewards(address to, uint256 amount) external {
        require(block.timestamp > _startTime, "Not started");
        require(amount > 0 && to > address(0), "Invalid params");
        UserInfo storage user = _users[msg.sender]; //storage or mem?

        // get pending + update state
        _harvest();

        // get user rewards
        uint256 totalRewards = (user.shares * _totalRewards) / _totalShares;

        //remove principal
        totalRewards = totalRewards - user.principle;

        if(amount < totalRewards) {
                revert("Insufficient rewards");
        } // or rebase

        //number of shares
        uint256 amountInShares = amount * _totalShares / _totalRewards;

        //update storage
        _totalRewards -= amount;
        _totalShares -= amountInShares;
        user.shares -= amountInShares;


        emit RewardsClaimed(msg.sender, to, amount);
    }

    // user specifies principle as amount, not shares.
    function redeem(address onBehalfOf, uint256 amount) external {
        require(block.timestamp > _startTime, "Not started");
        require(amount > 0 && onBehalfOf > address(0), "Invalid params");

        UserInfo storage user = _users[msg.sender]; //storage or mem?
        
        if(user.principle < amount) {
                revert("Insufficient principle");
        } // or rebase

        //in shares
        uint256 amountInShares = amount * _totalShares / _totalRewards;

        //update storage
        _totalShares -= amountInShares;
        user.shares -= amountInShares;
        user.principle -= amount;

        //transfer
        token.safeTransfer(onBehalfOf, amount);

        emit Redeem(msg.sender, onBehalfOf, amount);
    }

    function _harvest() internal {
        // 2 txns in the same block -> same block.timestamp
        if (block.timestamp > _lastUpdateTime) {
            uint256 rewardsEmitted = (block.timestamp - _lastUpdateTime) * _emissionPerSecond;

            // update storage
            _totalRewardsHarvested += rewardsEmitted;
            if (_totalShares > 0) {
                _totalRewards += rewardsEmitted; // so that on first deposit, there are no rewards, inflating
                    // ex.rate
            }

            //transfer
            token.safeTransferFrom(vault, address(this), rewardsEmitted);

            emit RewardsHarvested(address(token), rewardsEmitted);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    function balanceOf() public view returns (uint256) {
        return token.balanceOf(address(this));
    }
}
