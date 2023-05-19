// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ILiquidityPoolCodeHashRegistry {
    function isValidCodeHash(bytes32 codehash) external view returns(bool);
}