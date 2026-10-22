// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {FarmingSeason} from "src/FarmingSeason.sol";

/// @dev Complements the original deployment/ERC-20 tests with allowance lifecycle and boundary properties.
/// forge-config: default.fuzz.runs = 1024
contract FarmingSeasonPropertiesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;

    FarmingSeason private token;
    address private alice;
    address private bob;
    address private spender;

    function setUp() public {
        token = new FarmingSeason();
        alice = makeAddr("properties-alice");
        bob = makeAddr("properties-bob");
        spender = makeAddr("properties-spender");
    }

    function test_oneSmallestUnitMovesWithoutRounding() public {
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        assertEq(token.balanceOf(alice), 1);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 1);
        _assertConservation();
    }

    function test_selfTransferStillRequiresSufficientBalance() public {
        token.transfer(alice, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        vm.prank(alice);
        token.transfer(alice, 2);
        assertEq(token.balanceOf(alice), 1);
        _assertConservation();
    }

    function test_delegatedSelfTransferStillRequiresSufficientBalance() public {
        token.transfer(alice, 1);
        vm.prank(alice);
        token.approve(spender, 2);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        vm.prank(spender);
        token.transferFrom(alice, alice, 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.allowance(alice, spender), 2, "failed self-transfer consumed approval");
        _assertConservation();
    }

    function test_largestFiniteAllowanceIsConsumed() public {
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
        assertEq(token.balanceOf(alice), 1);
        _assertConservation();
    }

    function test_infiniteApprovalCanBeDowngradedAndRevoked() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        token.approve(spender, 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), 1);

        token.approve(spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(alice), 2);
        _assertConservation();
    }

    function test_infiniteAllowanceDoesNotBypassBalanceOrReceiverValidation() public {
        token.approve(spender, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 1);
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        // An exact-balance transfer remains possible after both failures.
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        _assertConservation();
    }

    function test_zeroDelegatedTransferToZeroRevertsWithEveryApprovalMode() public {
        uint256[4] memory approvals = [uint256(0), uint256(1), type(uint256).max - 1, type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            token.approve(spender, approvals[i]);
            vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
            vm.prank(spender);
            token.transferFrom(address(this), address(0), 0);
            assertEq(token.allowance(address(this), spender), approvals[i]);
        }
        assertEq(token.balanceOf(address(this)), SUPPLY);
        _assertConservation();
    }

    function test_approvalBeforeFundingSurvivesEmptyingAndRefilling() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 2));
        assertEq(token.balanceOf(alice), 0);
        token.transfer(alice, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(alice, spender), 1);

        token.transfer(alice, 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, spender), 0);

        // Receiving more tokens must not resurrect a spent approval.
        token.transfer(alice, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 2);
        _assertConservation();
    }

    function test_spenderCannotDelegateSomeoneElsesApproval() public {
        token.approve(alice, 10);
        vm.prank(alice);
        token.approve(spender, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), alice), 10);
        assertEq(token.allowance(alice, spender), 10);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        _assertConservation();
    }

    function testFuzz_transferRoundTripPreservesBalancesAndApprovals(uint256 amount, uint256 approval) public {
        amount = bound(amount, 0, SUPPLY);
        token.approve(spender, approval);
        vm.prank(alice);
        token.approve(bob, approval);

        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), amount);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), amount));

        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.allowance(address(this), spender), approval);
        assertEq(token.allowance(alice, bob), approval);
        _assertConservation();
    }

    function testFuzz_approvalReplacementIsExactAndIdempotent(uint256 oldApproval, uint256 replacement) public {
        token.approve(spender, oldApproval);
        token.approve(bob, oldApproval);
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        assertEq(token.allowance(address(this), bob), oldApproval, "replacement changed another spender's approval");
        assertEq(token.balanceOf(address(this)), SUPPLY);
        _assertConservation();
    }

    function testFuzz_cumulativeSpendingCannotExceedApproval(uint256 approval, uint256 first) public {
        approval = bound(approval, 1, SUPPLY - 1);
        first = bound(first, 1, approval);
        token.approve(spender, approval);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, first));

        uint256 remaining = approval - first;
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, remaining, remaining + 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, remaining + 1);
        assertEq(token.allowance(address(this), spender), remaining);
        assertEq(token.balanceOf(alice), first);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, remaining));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), approval);
        assertEq(token.balanceOf(address(this)), SUPPLY - approval);
        _assertConservation();
    }

    function testFuzz_multipleSpendersCannotCollectMoreThanHolderBalance(uint256 balance, uint256 first) public {
        balance = bound(balance, 1, SUPPLY);
        first = bound(first, 1, balance);
        token.transfer(alice, balance);
        vm.startPrank(alice);
        token.approve(spender, balance);
        token.approve(bob, balance);
        vm.stopPrank();

        vm.prank(spender);
        assertTrue(token.transferFrom(alice, spender, first));
        uint256 remaining = balance - first;
        // Bob still has sufficient allowance; the holder's shared balance is the limit.
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, remaining, remaining + 1)
        );
        vm.prank(bob);
        token.transferFrom(alice, bob, remaining + 1);
        assertEq(token.allowance(alice, bob), balance);
        assertEq(token.balanceOf(alice), remaining);

        vm.prank(bob);
        assertTrue(token.transferFrom(alice, bob, remaining));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(spender), first);
        assertEq(token.balanceOf(bob), remaining);
        assertEq(token.allowance(alice, spender), remaining);
        assertEq(token.allowance(alice, bob), first);
        _assertConservation();
    }

    function testFuzz_balanceFailureRetainsApprovalForRetry(uint256 balance, uint256 deficit, uint256 approval) public {
        balance = bound(balance, 0, SUPPLY - 1);
        deficit = bound(deficit, 1, SUPPLY - balance);
        uint256 amount = balance + deficit;
        approval = bound(approval, amount, type(uint256).max);
        token.transfer(alice, balance);
        vm.prank(alice);
        token.approve(spender, approval);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approval);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);

        token.transfer(alice, deficit);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(alice, spender), approval == type(uint256).max ? approval : approval - amount);
        _assertConservation();
    }

    function _assertConservation() private view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(
            token.balanceOf(address(this)) + token.balanceOf(alice) + token.balanceOf(bob) + token.balanceOf(spender),
            SUPPLY
        );
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }
}
