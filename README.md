## GlobalStorage

Neutral, permissionless, namespaced key-value store intended to enable Top-of-Block (ToB) oracle updates. Writers publish values under their own address; readers fetch by `(owner, key)` and can enforce freshness via last-updated metadata.

- Status: Proposal (MVP)
- This README is the canonical design document.

### Why ToB?

With builder/relay policy that treats `to == GlobalStorage` transactions as ToB, latency-sensitive oracle updates can land at the top of the block without allowlists or privileged keys.

### Contract Overview

Main functions exposed by `src/IGlobalStorage.sol` / `src/GlobalStorage.sol`:

- `set(bytes32 key, bytes32 value)`
- `setBatch(bytes32[] keys, bytes32[] values)`
- `get(address owner, bytes32 key) -> bytes32`
- `getWithTimestamp(address owner, bytes32 key) -> (bytes32 value, uint64 blockTimestamp, uint64 blockNumber)`
- `latestUpdateBlock(address owner, bytes32 key) -> uint64`
- `latestUpdateTimestamp(address owner, bytes32 key) -> uint64`

Events:

- `GlobalValueSet(owner, key, value, blockNumber, timestamp)`
- `GlobalValuesSet(owner, keys, values, blockNumber, timestamp)`

### Design Document

Status: Proposal (MVP)

Owner: You

Scope: EVM-compatible chains; builder/relay policy dependent for ToB effect

#### 1) Goal

Enable neutral, nonpreferential, non-allowlist Top-of-Block (ToB) placement for oracle updates by routing them through a benign `GlobalStorage` contract that any participant can use. Provide a simple, permissionless interface for writers to publish ToB state and for readers (AMMs, perps, RFQ engines) to consume those values in the same or subsequent blocks.

#### 2) Core Idea

- Any transaction whose `to` equals `GlobalStorage` is treated by builders as an “oracle update” and moved into the ToB tranche regardless of priority fee. This requires builder policy but avoids allowlists or privileged keys.
- The contract is minimal and neutral: it only allows setting/getting values in storage slots namespaced by the sender’s address.
- Writers call `set(bytes32 key, bytes32 value)` or `setBatch(keys, values)`.
- Readers fetch values via `get(address owner, bytes32 key)` (and freshness helpers).
- Namespacing: `mapping(address => mapping(bytes32 => bytes32))` to ensure writers only mutate their own keys.

#### 3) Actors and Flows

- Writer (market maker/oracle agent):
  1. Compute `key = keccak256(abi.encode(tokenIn, tokenOut))` (or another agreed schema).
  2. Submit transaction with `tx.to = GlobalStorage`, calling `set(key, value)`.
  3. Builder policy places this tx in the ToB tranche.

- Reader (AMM / perps / on-chain consumers):
  - In price-sensitive execution, read `GlobalStorage.get(owner, key)` and optionally enforce freshness via `latestUpdateBlock(owner, key) == block.number`.

- Builders/Proposers:
  - Adopt a public, verifiable policy: all `to == GlobalStorage` txs receive ToB ordering.
  - Publish commitments/attestations (signed statements; MEV-Boost relay metadata/policies).

#### 4) Contract Design

- Immutability and neutrality:
  - No owner, no governance, no pausable logic.
  - No privileged writes; each sender may only write its own namespace.
  - No fees or external calls; minimal surface area for risk.

- Solidity interface (MVP):

```solidity
/// @notice Neutral, namespaced key-value store for ToB oracle updates.
interface IGlobalStorage {
    /// @dev Sets a value in the caller's namespace.
    function set(bytes32 key, bytes32 value) external;

    /// @dev Sets multiple values in the caller's namespace.
    function setBatch(bytes32[] calldata keys, bytes32[] calldata values) external;

    /// @dev Reads a value in `owner`'s namespace.
    function get(address owner, bytes32 key) external view returns (bytes32);

    /// @dev Returns value with last update time metadata.
    function getWithTimestamp(address owner, bytes32 key)
        external
        view
        returns (bytes32 value, uint64 blockTimestamp, uint64 blockNumber);

    /// @dev Returns the last update block number for the given key.
    function latestUpdateBlock(address owner, bytes32 key) external view returns (uint64);

    /// @dev Returns the last update timestamp for the given key.
    function latestUpdateTimestamp(address owner, bytes32 key) external view returns (uint64);

    /// @dev Emitted on single write.
    event GlobalValueSet(
        address indexed owner,
        bytes32 indexed key,
        bytes32 value,
        uint64 blockNumber,
        uint64 timestamp
    );

    /// @dev Emitted on batch write.
    event GlobalValuesSet(
        address indexed owner,
        bytes32[] keys,
        bytes32[] values,
        uint64 blockNumber,
        uint64 timestamp
    );
}
```

- Storage layout:
  - `mapping(address => mapping(bytes32 => bytes32)) valueOf;`
  - `mapping(address => mapping(bytes32 => uint64)) lastUpdateBlock;`
  - `mapping(address => mapping(bytes32 => uint64)) lastUpdateTimestamp;`

- Behavior:
  - `set` and `setBatch` update value and metadata; emit events.
  - No reentrancy (no external calls), no governance.

#### 5) Keying Scheme

- Token pair key (directional):
  - `bytes32 key = keccak256(abi.encode(tokenIn, tokenOut))`.
- Canonicalized pair (unordered):
  - Sort addresses and encode: `keccak256(abi.encode(min(tokenA, tokenB), max(tokenA, tokenB)))`.
- Rich schema examples:
  - `keccak256(abi.encode("PAIR_PRICE_Q64_64", tokenIn, tokenOut))`.
  - `keccak256(abi.encode("ASSET_TWAP", token, windowSec))`.
  - `keccak256(abi.encode("VERSIONED", tokenIn, tokenOut, uint256(version)))`.

#### 6) Reader Integration Patterns

- AMM read-to-execute:
  - On swap, read `value = get(oracleWriter, key)` and assert `latestUpdateBlock(oracleWriter, key) == block.number` to ensure ToB freshness.
  - Apply slippage bands anchored to `value`.
- Perps latency-sensitive flows:
  - Use ToB update to constrain mark price for order acceptance; settle with delayed oracles later.
- Safety/fallbacks:
  - If stale/missing, fallback to TWAP/Chainlink, widen spreads, or revert based on policy.

#### 7) Builder/Relay Policy

- Public ToB rule: “All transactions with `to == GlobalStorage` are placed in the ToB bucket.”
- Resource limits: Builders cap ToB bucket gas (e.g., 3–5% of block gas) to mitigate grief.
- Ordering within ToB: FIFO by arrival time or base fee; nonpreferential across senders.
- Verifiability: Builders publish signed policy docs or embed policy hash in relay metadata.

#### 8) Trust & Adversarial Model

- Neutrality: Contract enforces only per-sender namespaces. No allowlists.
- Abuse vectors:
  - Storage spam: mitigated by gas costs and ToB bucket gas caps.
  - Malicious values: readers pin to trusted `owner` address(es). Do not read from arbitrary owners.
- MEV considerations: Other ToB users may also write; readers must bind to specific `owner`.

#### 9) Gas & Performance (MVP estimates)

- `set`: 1–3 SSTOREs (value + metadata). New slot: ~20k, warm updates lower.
- `setBatch`: amortizes overhead; enforce a reasonable max length to avoid exceeding block gas.
- `get`: cheap SLOADs; negligible overhead.

#### 10) Public API and ABI

- `set(bytes32 key, bytes32 value)`
- `setBatch(bytes32[] keys, bytes32[] values)`
- `get(address owner, bytes32 key) -> bytes32`
- `getWithTimestamp(address owner, bytes32 key) -> (bytes32,uint64,uint64)`
- `latestUpdateBlock(address owner, bytes32 key) -> uint64`
- `latestUpdateTimestamp(address owner, bytes32 key) -> uint64`

#### 11) Deterministic Deployment

- Same bytecode across chains; deploy with CREATE2 and publish salt.
- Maintain a public registry mapping `chainId -> contractAddress -> bytecodeHash`.

#### 12) Security Considerations

- Reentrancy: None (no external calls).
- Integer safety: Use Solidity 0.8+; cast to `uint64` with explicit range checks.
- Event spoofing: Readers must rely on storage state, not solely events.
- Access control: Writes restricted to `msg.sender` namespace.

#### 13) Compliance With ToB Principle

- ToB is achieved via off-chain builder/relay policy and is best-effort. The contract remains useful without ToB (just higher latency). Document the assumption clearly for integrators.

#### 14) Rollout Plan

1. Deploy contract; publish ABI and address per chain.
2. Coordinate with builders/relays to adopt the ToB policy (publish signatures/attestations).
3. Release a reference AMM adapter demonstrating read path + safety checks.
4. Add observability: dashboard for freshness and ToB share metrics.

#### 15) Example Usage

- Writer (price push):

```solidity
bytes32 key = keccak256(abi.encode(tokenIn, tokenOut));
bytes32 priceQ64_64 = bytes32(uint256(priceX128 >> 64)); // example encoding
IGlobalStorage(GLOBAL_STORAGE_ADDR).set(key, priceQ64_64);
```

- Reader (during swap):

```solidity
(bytes32 v, uint64 ts, uint64 bn) = IGlobalStorage(GLOBAL_STORAGE_ADDR)
    .getWithTimestamp(oracleWriter, key);
require(bn == block.number, "stale");
// decode v as needed, apply slippage guards
```

#### 16) Open Questions

- Per-block sequence numbers to detect multiple writes in the same block?
- Builder-side per-sender quotas inside ToB bucket to avoid monopolization?
- Do we need `getAtBlock(owner, key, blockNumber)` ring buffer? (Likely no for MVP.)

### Quick Start (Foundry)

#### Build

```shell
$ forge build
```

#### Test

```shell
$ forge test
```

Run verbose tests for this project’s suite (see `test/GlobalStorage.t.sol`):

```shell
$ forge test -vv
```

#### Format

```shell
$ forge fmt
```

#### Gas Snapshots

```shell
$ forge snapshot
```

#### Local Node (Anvil)

```shell
$ anvil
```

### Deploy

Deploy the contract with Foundry:

```shell
$ forge create src/GlobalStorage.sol:GlobalStorage \
  --rpc-url <your_rpc_url> \
  --private-key <your_private_key>
```

Alternatively, use your own deployment script.

### Integration Snippets

Writer pushes a value under their namespace:

```solidity
bytes32 key = keccak256(abi.encode(tokenIn, tokenOut));
bytes32 priceQ64_64 = bytes32(uint256(priceX128 >> 64));
IGlobalStorage(GLOBAL_STORAGE_ADDR).set(key, priceQ64_64);
```

Reader fetches and enforces freshness in the same block:

```solidity
(bytes32 value, uint64 ts, uint64 bn) = IGlobalStorage(GLOBAL_STORAGE_ADDR)
    .getWithTimestamp(oracleWriter, key);
require(bn == block.number, "stale");
```

For more context, examples, and keying schemes, see the design sections above and the tests in `test/GlobalStorage.t.sol`.

### Notes

- ToB behavior depends on off-chain builder/relay policy; the contract itself is neutral and permissionless.
- Each sender writes only to their own namespace (`msg.sender`). Consumers should read from trusted `owner` addresses.

### License

MIT

### Foundry Docs

https://book.getfoundry.sh/
