// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {FarmingSeason} from "../src/FarmingSeason.sol";

/// @dev Tracks an independent model across valid and invalid randomized operations.
contract SeasonHandler is Test {
    FarmingSeason public immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(FarmingSeason token_) {
        token = token_;
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("holder-", vm.toString(i)));
        }
        expectedBalance[actors[0]] = token_.INITIAL_SUPPLY();
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        // Include exact-balance transfers, zero transfers, and attempts above the balance.
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(rawAmount, 0, balance + 1);
        vm.prank(from);
        (bool success,) = address(token).call(abi.encodeCall(token.transfer, (to, amount)));
        if (amount > balance) {
            assertFalse(success, "overspending balance succeeded");
        } else {
            assertTrue(success, "valid transfer reverted");
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
        }
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 rawAmount) external {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 approved = expectedAllowance[from][spender];
        uint256 spendable = balance < approved ? balance : approved;
        uint256 amount = bound(rawAmount, 0, spendable + 1);
        vm.prank(spender);
        (bool success,) = address(token).call(abi.encodeCall(token.transferFrom, (from, to, amount)));
        if (amount > spendable) {
            assertFalse(success, "unauthorized or unfunded transfer succeeded");
        } else {
            assertTrue(success, "valid delegated transfer reverted");
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
            if (approved != type(uint256).max) {
                expectedAllowance[from][spender] -= amount;
            }
        }
    }
}

contract FarmingSeasonInvariantTest is StdInvariant, Test {
    FarmingSeason private token;
    SeasonHandler private handler;

    function setUp() public {
        token = new FarmingSeason();
        handler = new SeasonHandler(token);
        token.transfer(handler.actors(0), token.INITIAL_SUPPLY());

        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = SeasonHandler.approve.selector;
        selectors[1] = SeasonHandler.transfer.selector;
        selectors[2] = SeasonHandler.transferFrom.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyAndBalancesAlwaysMatchModel() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor));
            sum += balance;
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(actor, spender), handler.expectedAllowance(actor, spender));
            }
        }
        assertEq(sum, 1_000_000_000 * 10 ** 18);
        assertEq(token.totalSupply(), sum);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }
}
