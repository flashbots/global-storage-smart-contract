// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "../lib/forge-std/src/Test.sol";
import {IGlobalStorage} from "../src/IGlobalStorage.sol";
import {GlobalStorage} from "../src/GlobalStorage.sol";

contract GlobalStorageTest is Test {
    GlobalStorage internal gs;
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        gs = new GlobalStorage();
    }

    function testSetAndGet() public {
        bytes32 key = keccak256(abi.encode(address(1), address(2)));
        bytes32 val = bytes32(uint256(123));

        vm.prank(alice);
        gs.set(key, val);

        assertEq(gs.get(alice, key), val);
        (bytes32 value, uint64 timestamp, uint64 blockNumber) = gs.getWithTimestamp(alice, key);
        assertEq(value, val);
        assertEq(blockNumber, uint64(block.number));
        assertGt(timestamp, 0);

        uint64 lastBlockNumber = gs.latestUpdateBlock(alice, key);
        uint64 lastTimestamp = gs.latestUpdateTimestamp(alice, key);
        assertEq(lastBlockNumber, blockNumber);
        assertEq(lastTimestamp, timestamp);
    }

    function testNamespacesIsolation() public {
        bytes32 key = keccak256("PAIR");
        bytes32 aliceVal = bytes32(uint256(42));
        bytes32 bobVal = bytes32(uint256(43));

        vm.prank(alice);
        gs.set(key, aliceVal);
        vm.prank(bob);
        gs.set(key, bobVal);

        assertEq(gs.get(alice, key), aliceVal);
        assertEq(gs.get(bob, key), bobVal);
        assertTrue(gs.get(alice, key) != gs.get(bob, key));
    }

    function testSetBatch() public {
        vm.prank(bob);
        bytes32[] memory keys = new bytes32[](2);
        bytes32[] memory vals = new bytes32[](2);
        keys[0] = keccak256("k1");
        vals[0] = bytes32(uint256(1));
        keys[1] = keccak256("k2");
        vals[1] = bytes32(uint256(2));

        gs.setBatch(keys, vals);

        assertEq(gs.get(bob, keys[0]), vals[0]);
        assertEq(gs.get(bob, keys[1]), vals[1]);

        (bytes32 v0,, uint64 blockNumber0) = gs.getWithTimestamp(bob, keys[0]);
        (bytes32 v1,, uint64 blockNumber1) = gs.getWithTimestamp(bob, keys[1]);
        assertEq(v0, vals[0]);
        assertEq(v1, vals[1]);
        assertEq(blockNumber0, blockNumber1);
    }

    function testSetBatchRevertsOnLengthMismatch() public {
        vm.prank(alice);
        bytes32[] memory keys = new bytes32[](1);
        bytes32[] memory vals = new bytes32[](2);
        keys[0] = keccak256("k1");
        vals[0] = bytes32(uint256(1));
        vals[1] = bytes32(uint256(2));

        vm.expectRevert(GlobalStorage.MismatchedInputLengths.selector);
        gs.setBatch(keys, vals);
    }

    // --- Mocked Prop AMM quote test ---

    function _key(string memory s) internal pure returns (bytes32) {
        return keccak256(bytes(s));
    }

    function _mockQuoteXToY_ETH_USDC(address owner, uint256 amountInWei)
        internal
        view
        returns (uint256 amountOutUsdc, uint256 fee)
    {
        // Read parameters from GlobalStorage for the ETH-USDC pair.
        // Only concentration, fee, mult_x, mult_y are used by this simple mocked rule.
        uint256 concentration = uint256(gs.get(owner, _key("ETH_USDC_CONCENTRATION")));
        uint256 feeMillionth = uint256(gs.get(owner, _key("ETH_USDC_FEE_MILLIONTH")));
        uint256 multX = uint256(gs.get(owner, _key("ETH_USDC_MULT_X")));
        uint256 reserveY = uint256(gs.get(owner, _key("ETH_USDC_RESERVE_Y")));

        // Mocked pricing rule:
        // amount_out = amount_in * concentration / mult_x
        // where concentration encodes the price in quote units scaled by mult_y.
        amountOutUsdc = amountInWei * concentration / multX;
        fee = amountOutUsdc * feeMillionth / 1_000_000;
        amountOutUsdc -= fee;

        require(amountOutUsdc < reserveY, "insufficient reserveY");
    }

    function testMockQuote_ETH_USDC_1ETH_to_4000USDC() public {
        // Publisher (alice) writes ETH-USDC parameters to GlobalStorage.
        bytes32[] memory keys = new bytes32[](7);
        bytes32[] memory vals = new bytes32[](7);

        // Chosen values: price = 4000 USDC per 1 ETH
        // mult_x = 1e18 (ETH decimals), mult_y = 1e6 (USDC decimals)
        // concentration encodes price * mult_y = 4000 * 1e6
        keys[0] = _key("ETH_USDC_TARGET_X");
        vals[0] = bytes32(uint256(0));
        keys[1] = _key("ETH_USDC_CONCENTRATION");
        vals[1] = bytes32(uint256(4000 * 1e6));
        keys[2] = _key("ETH_USDC_RESERVE_X");
        vals[2] = bytes32(uint256(100 ether));
        keys[3] = _key("ETH_USDC_RESERVE_Y");
        vals[3] = bytes32(uint256(10_000_000 * 1e6));
        keys[4] = _key("ETH_USDC_FEE_MILLIONTH");
        vals[4] = bytes32(uint256(0));
        keys[5] = _key("ETH_USDC_MULT_X");
        vals[5] = bytes32(uint256(1e18));
        keys[6] = _key("ETH_USDC_MULT_Y");
        vals[6] = bytes32(uint256(1e6));

        vm.prank(alice);
        gs.setBatch(keys, vals);

        uint256 amountIn = 1 ether; // 1 ETH
        (uint256 amountOut, uint256 fee) = _mockQuoteXToY_ETH_USDC(alice, amountIn);

        assertEq(fee, 0);
        assertEq(amountOut, 4000 * 1e6); // 4000 USDC (6 decimals)
    }
}
