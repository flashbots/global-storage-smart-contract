// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/// @title IGlobalStorage
/// @notice Neutral, namespaced key-value store interface for ToB prop AMM updates.
interface IGlobalStorage {
    /// @notice Sets a value in the caller's namespace.
    /// @param key The key within the caller's namespace.
    /// @param value The value to set for the given key.
    function set(bytes32 key, bytes32 value) external;

    /// @notice Sets multiple values in the caller's namespace.
    /// @param keys The keys to set.
    /// @param values The values to set for the corresponding keys.
    function setBatch(bytes32[] calldata keys, bytes32[] calldata values) external;

    /// @notice Reads a value in `owner`'s namespace.
    /// @param owner The namespace owner to read from.
    /// @param key The key to read.
    /// @return value The stored value or zero if unset.
    function get(address owner, bytes32 key) external view returns (bytes32 value);

    /// @notice Emitted on single write.
    /// @param owner The namespace owner (i.e., msg.sender).
    /// @param key The key that was set.
    /// @param value The value that was set.
    /// @param blockNumber The block number when the set occurred.
    /// @param timestamp The timestamp when the set occurred.
    event GlobalValueSet(
        address indexed owner, bytes32 indexed key, bytes32 value, uint64 blockNumber, uint64 timestamp
    );

    /// @notice Emitted on batch write.
    /// @param owner The namespace owner (i.e., msg.sender).
    /// @param keys The keys that were set.
    /// @param values The values that were set.
    /// @param blockNumber The block number when the set occurred.
    /// @param timestamp The timestamp when the set occurred.
    event GlobalValuesSet(
        address indexed owner, bytes32[] keys, bytes32[] values, uint64 blockNumber, uint64 timestamp
    );
}
