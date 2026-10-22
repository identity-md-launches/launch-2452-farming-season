// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {FarmingSeason} from "../src/FarmingSeason.sol";

/// @dev Tracks an independent model across valid and invalid randomized operations.
contract SeasonHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    FarmingSeason public immutable token;
    address public immutable deployer;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(FarmingSeason token_) {
        token = token_;
        deployer = msg.sender;
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("holder-", vm.toString(i)));
        }
        // The oracle starts from the requested supply, not a value read from the implementation.
        expectedBalance[actors[0]] = SUPPLY;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 rawAmount, uint8 mode) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        // Reach useful finite approvals, unlimited approvals, revocation, and the full uint256 domain.
        uint256 kind = mode % 4;
        uint256 amount =
            kind == 0 ? bound(rawAmount, 0, SUPPLY) : kind == 1 ? type(uint256).max : kind == 2 ? 0 : rawAmount;
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 rawAmount, uint8 mode) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 amount = _amount(rawAmount, balance, mode);
        if (amount > balance) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
            );
            vm.prank(from);
            token.transfer(to, amount);
        } else {
            vm.prank(from);
            assertTrue(token.transfer(to, amount), "valid transfer did not return true");
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
        }
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 rawAmount, uint8 mode)
        external
    {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        uint256 approved = expectedAllowance[from][spender];
        uint256 spendable = balance < approved ? balance : approved;
        uint256 amount = _amount(rawAmount, spendable, mode);
        if (amount > approved) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, amount)
            );
            vm.prank(spender);
            token.transferFrom(from, to, amount);
        } else if (amount > balance) {
            vm.expectRevert(
                abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, amount)
            );
            vm.prank(spender);
            token.transferFrom(from, to, amount);
        } else {
            vm.prank(spender);
            assertTrue(token.transferFrom(from, to, amount), "valid delegated transfer did not return true");
            expectedBalance[from] -= amount;
            expectedBalance[to] += amount;
            if (approved != type(uint256).max) {
                expectedAllowance[from][spender] -= amount;
            }
        }
    }

    function transferToZero(uint256 fromSeed, uint256 rawAmount) external {
        address from = actors[fromSeed % actors.length];
        uint256 amount = bound(rawAmount, 0, expectedBalance[from]);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(from);
        token.transfer(address(0), amount);
        // No ghost updates: the invariant checks that the rejected call changed nothing.
    }

    function transferFromToZero(uint256 spenderSeed, uint256 fromSeed, uint256 rawAmount) external {
        address spender = actors[spenderSeed % actors.length];
        address from = actors[fromSeed % actors.length];
        uint256 approved = expectedAllowance[from][spender];
        uint256 balance = expectedBalance[from];
        uint256 amount = bound(rawAmount, 0, balance < approved ? balance : approved);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(from, address(0), amount);
        // In particular, any finite allowance spent before the receiver check must be restored.
    }

    function approveZero(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    function forbiddenCall(uint256 callerSeed, uint256 holderSeed, uint256 amount, uint8 operation) external {
        // Include the original deployer, who must have no lingering authority over holders.
        address caller = callerSeed % 5 == 4 ? deployer : actors[callerSeed % actors.length];
        address holder = actors[holderSeed % actors.length];
        bytes memory data;
        uint256 kind = operation % 6;
        if (kind == 0) data = abi.encodeWithSignature("mint(address,uint256)", holder, amount);
        else if (kind == 1) data = abi.encodeWithSignature("burnFrom(address,uint256)", holder, amount);
        else if (kind == 2) data = abi.encodeWithSignature("pause()");
        else if (kind == 3) data = abi.encodeWithSignature("blacklist(address)", holder);
        else if (kind == 4) data = abi.encodeWithSignature("initialize(address)", holder);
        else data = abi.encodeWithSignature("seize(address)", holder);
        vm.prank(caller);
        (bool success,) = address(token).call(data);
        assertFalse(success, "unexpected administrative entry point");
    }

    function _amount(uint256 rawAmount, uint256 available, uint8 mode) private pure returns (uint256) {
        uint256 kind = mode % 6;
        if (kind == 0) return 0;
        if (kind == 1) return 1;
        if (kind == 2) return available;
        if (kind == 3) return available + 1;
        if (kind == 4) return type(uint256).max;
        return bound(rawAmount, 0, available);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract FarmingSeasonInvariantTest is StdInvariant, Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    FarmingSeason private token;
    SeasonHandler private handler;

    function setUp() public {
        token = new FarmingSeason();
        handler = new SeasonHandler(token);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertTrue(token.transfer(handler.actors(0), SUPPLY));

        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = SeasonHandler.approve.selector;
        selectors[1] = SeasonHandler.transfer.selector;
        selectors[2] = SeasonHandler.transferFrom.selector;
        selectors[3] = SeasonHandler.transferToZero.selector;
        selectors[4] = SeasonHandler.transferFromToZero.selector;
        selectors[5] = SeasonHandler.approveZero.selector;
        selectors[6] = SeasonHandler.forbiddenCall.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_supplyAndBalancesAlwaysMatchModel() public view {
        uint256 sum;
        for (uint256 i; i < 4; ++i) {
            address actor = handler.actors(i);
            uint256 balance = token.balanceOf(actor);
            assertEq(balance, handler.expectedBalance(actor));
            assertEq(token.allowance(actor, address(0)), 0);
            assertEq(token.allowance(address(0), actor), 0);
            sum += balance;
            for (uint256 j; j < 4; ++j) {
                address spender = handler.actors(j);
                assertEq(token.allowance(actor, spender), handler.expectedAllowance(actor, spender));
            }
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), sum);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.name(), "Farming Season");
        assertEq(token.symbol(), "SEASON");
        assertEq(token.decimals(), 18);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    /// @dev Every holder can still move their entire balance after any generated sequence.
    function afterInvariant() public {
        for (uint256 i; i < 4; ++i) {
            handler.transfer(i, (i + 1) % 4, 0, 2);
        }
        assertEq(token.balanceOf(handler.actors(0)), SUPPLY);
        invariant_supplyAndBalancesAlwaysMatchModel();
    }
}
