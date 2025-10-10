// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IGlobalStorage} from "./IGlobalStorage.sol";

/// @title GlobalStorage
/// @notice Neutral, namespaced key-value store for ToB oracle updates.
/// Each sender can set values in their own namespace; readers can fetch by (owner, key).
contract GlobalStorage is IGlobalStorage {
    /// @dev Stored values by namespace owner and key.
    mapping(address => mapping(bytes32 => bytes32)) private valueOf;

    /// @dev Packed metadata (timestamp in high 64 bits, block number in low 64 bits).
    mapping(address => mapping(bytes32 => uint128)) private lastUpdatePacked;

    /// @dev Revert when keys and values array lengths do not match.
    error MismatchedInputLengths();

    /// @inheritdoc IGlobalStorage
    function set(bytes32 key, bytes32 value) external {
        valueOf[msg.sender][key] = value;
        uint64 bn = uint64(block.number);
        uint64 ts = uint64(block.timestamp);
        uint128 packed = (uint128(ts) << 64) | uint128(bn);
        lastUpdatePacked[msg.sender][key] = packed;
        emit GlobalValueSet(msg.sender, key, value, bn, ts);
    }

    /// @inheritdoc IGlobalStorage
    function setBatch(bytes32[] calldata keys, bytes32[] calldata values) external {
        if (keys.length != values.length) revert MismatchedInputLengths();
        uint64 bn = uint64(block.number);
        uint64 ts = uint64(block.timestamp);
        uint128 packed = (uint128(ts) << 64) | uint128(bn);
        for (uint256 i = 0; i < keys.length; i++) {
            bytes32 key = keys[i];
            bytes32 value = values[i];
            valueOf[msg.sender][key] = value;
            lastUpdatePacked[msg.sender][key] = packed;
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
        uint128 packed = lastUpdatePacked[owner][key];
        uint64 bn = uint64(packed);
        uint64 ts = uint64(packed >> 64);
        return (valueOf[owner][key], ts, bn);
    }

    /// @inheritdoc IGlobalStorage
    function latestUpdateBlock(address owner, bytes32 key) external view returns (uint64) {
        uint128 packed = lastUpdatePacked[owner][key];
        return uint64(packed);
    }

    /// @inheritdoc IGlobalStorage
    function latestUpdateTimestamp(address owner, bytes32 key) external view returns (uint64) {
        uint128 packed = lastUpdatePacked[owner][key];
        return uint64(packed >> 64);
    }
}
