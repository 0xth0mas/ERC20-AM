
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ILiquidityPoolCodeHashRegistry} from './ILiquidityPoolCodeHashRegistry.sol';

contract LiquidityPoolCodeHashRegistry is ILiquidityPoolCodeHashRegistry {
    address public codeHashUpdateMultisig = 0x1234567890123456789012345678901234567890;

    mapping(bytes32 => bool) public allowedCodeHash;

    error NotAuthorized();

    function setCodeHash(bytes32 codehash, bool allowed) external {
        if(msg.sender != codeHashUpdateMultisig) revert NotAuthorized();
        allowedCodeHash[codehash] = allowed;
    }

    function isValidCodeHash(bytes32 codehash) external view returns(bool allowed) {
        allowed = allowedCodeHash[codehash];
    }
}