// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {StakingPoolIndexStorage} from "./StakingPoolIndexStorage.sol";
import {ERC1967Proxy} from "openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title Proxy for UUPS implementation
/// @author Calnix
contract StakingPoolProxy is ERC1967Proxy {

    /**
     * @dev Initializes the upgradeable proxy with an initial implementation specified by `_logic`.
     *
     * If `_data` is nonempty, it's used as data in a delegate call to `_logic`. This will typically be an encoded
     * function call, and allows initializing the storage of the proxy like a Solidity constructor.
     */
    constructor(address _logic, bytes memory _data) ERC1967Proxy(_logic, _data){
    }


    /// @dev Returns the current implementation address.
    function implementation() external view returns (address impl) {
        return _implementation();
    }

}