// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IGlobalStorage} from "./IGlobalStorage.sol";

/// @title GlobalStorage
/// @notice Neutral, namespaced key-value store for ToB oracle updates.
/// Each sender can set values in their own namespace; readers can fetch by (owner, key).
contract GlobalStorage is IGlobalStorage {
    /// @dev Stored value per (owner, key).
    mapping(address => mapping(bytes32 => bytes32)) private valueOf;

    /// @dev Revert when keys and values array lengths do not match.
    error MismatchedInputLengths();

    /// @inheritdoc IGlobalStorage
    function set(bytes32 key, bytes32 value) external {
        address owner = msg.sender;
        uint64 blockNumber = uint64(block.number);
        uint64 timestamp = uint64(block.timestamp);
        valueOf[owner][key] = value;
        emit GlobalValueSet(owner, key, value, blockNumber, timestamp);
    }

    /// @inheritdoc IGlobalStorage
    function setBatch(bytes32[] calldata keys, bytes32[] calldata values) external {
        if (keys.length != values.length) revert MismatchedInputLengths();
        address owner = msg.sender;
        uint64 blockNumber = uint64(block.number);
        uint64 timestamp = uint64(block.timestamp);
        uint256 len = keys.length;
        for (uint256 i = 0; i < len;) {
            bytes32 key = keys[i];
            valueOf[owner][key] = values[i];
            unchecked { ++i; }
        }
        emit GlobalValuesSet(owner, keys, values, blockNumber, timestamp);
    }

    /// @inheritdoc IGlobalStorage
    function get(address owner, bytes32 key) external view returns (bytes32 value) {
        return valueOf[owner][key];
    }
}
