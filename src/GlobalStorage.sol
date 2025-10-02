// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IGlobalStorage} from "./IGlobalStorage.sol";

/// @title GlobalStorage
/// @notice Neutral, namespaced key-value store for ToB oracle updates.
/// Each sender can set values in their own namespace; readers can fetch by (owner, key).
contract GlobalStorage is IGlobalStorage {
    /// @dev Stored values by namespace owner and key.
    mapping(address => mapping(bytes32 => bytes32)) private valueOf;

    /// @dev Metadata for last update block by owner and key.
    mapping(address => mapping(bytes32 => uint64)) private lastUpdateBlock;

    /// @dev Metadata for last update timestamp by owner and key.
    mapping(address => mapping(bytes32 => uint64)) private lastUpdateTimestamp;

    /// @dev Revert when keys and values array lengths do not match.
    error MismatchedInputLengths();

    /// @inheritdoc IGlobalStorage
    function set(bytes32 key, bytes32 value) external {
        valueOf[msg.sender][key] = value;
        uint64 bn = uint64(block.number);
        uint64 ts = uint64(block.timestamp);
        lastUpdateBlock[msg.sender][key] = bn;
        lastUpdateTimestamp[msg.sender][key] = ts;
        emit GlobalValueSet(msg.sender, key, value, bn, ts);
    }

    /// @inheritdoc IGlobalStorage
    function setBatch(bytes32[] calldata keys, bytes32[] calldata values) external {
        if (keys.length != values.length) revert MismatchedInputLengths();
        uint64 bn = uint64(block.number);
        uint64 ts = uint64(block.timestamp);
        for (uint256 i = 0; i < keys.length; i++) {
            bytes32 key = keys[i];
            bytes32 value = values[i];
            valueOf[msg.sender][key] = value;
            lastUpdateBlock[msg.sender][key] = bn;
            lastUpdateTimestamp[msg.sender][key] = ts;
        }
        emit GlobalValuesSet(msg.sender, keys, values, bn, ts);
    }

    /// @inheritdoc IGlobalStorage
    function get(address owner, bytes32 key) external view returns (bytes32 value) {
        return valueOf[owner][key];
    }

    /// @inheritdoc IGlobalStorage
    function getWithTimestamp(address owner, bytes32 key)
        external
        view
        returns (bytes32 value, uint64 blockTimestamp, uint64 blockNumber)
    {
        return (valueOf[owner][key], lastUpdateTimestamp[owner][key], lastUpdateBlock[owner][key]);
    }

    /// @inheritdoc IGlobalStorage
    function latestUpdateBlock(address owner, bytes32 key) external view returns (uint64) {
        return lastUpdateBlock[owner][key];
    }

    /// @inheritdoc IGlobalStorage
    function latestUpdateTimestamp(address owner, bytes32 key) external view returns (uint64) {
        return lastUpdateTimestamp[owner][key];
    }
}
