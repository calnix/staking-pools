// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { IERC20 } from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract Foo {
    using SafeERC20 for IERC20;

    IERC20 internal token;
    // vault

    struct UserInfo {
        uint256 principle; //denoted in asset
        uint256 shares; //total shares
            //uint256 lastUserActionTime;
    }

    mapping(address user => UserInfo userInfo) internal _users;

    uint256 internal _totalShares;
    uint256 internal _totalRewards;

    //Asset Index
    uint256 internal _emissionPerSecond;
    uint256 internal _totalRewardsHarvested;
    uint256 internal _totalRewardsEmitted;

    uint256 internal _totalStaked; // only principal staked
    //uint256 internal _lastUpdateTimeStamp;

    function deposit(uint256 amount) external {
        UserInfo storage user = _users[msg.sender]; //storage or mem?

        //get rewards from vault
        //harvest();

        // handle emitted unclaimed rewards
        // must remove to avoid inflation on first deposit
        if (_totalShares == 0) {
            uint256 stockAmount = balanceOf();
        }

        //updateUserShare
        uint256 newShares;
        if (_totalShares > 0) {
            newShares = (amount * _totalShares) / _totalRewards;
        } else {
            newShares = amount;
        }

        //update storage
        _totalShares += newShares;
        user.shares += newShares;

        // transfer in staking tokens
        if (amount > 0) {
            token.safeTransferFrom(msg.sender, address(this), amount);
        }
    }

    function harvest() public returns (uint256) { }

    /*//////////////////////////////////////////////////////////////
                                GETTERS
    //////////////////////////////////////////////////////////////*/

    function balanceOf() public view returns (uint256) {
        return token.balanceOf(address(this));
    }
}
