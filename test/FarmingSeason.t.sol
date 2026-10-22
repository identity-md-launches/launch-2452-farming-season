// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {FarmingSeason} from "../src/FarmingSeason.sol";

/// @dev Models deployment through a factory rather than a direct wallet deployment.
contract TokenFactoryProbe {
    function deploy() external returns (FarmingSeason) {
        return new FarmingSeason();
    }
}

contract FarmingSeasonTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;

    FarmingSeason private token;
    address private alice;
    address private bob;
    address private spender;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        alice = makeAddr("alice");
        bob = makeAddr("bob");
        spender = makeAddr("spender");
        token = new FarmingSeason();
    }

    function test_metadataAndEntireSupplyAtDeployment() public view {
        assertEq(token.name(), "Farming Season");
        assertEq(token.symbol(), "SEASON");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_constructorEmitsMintTransfer() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), address(this), SUPPLY);
        FarmingSeason deployed = new FarmingSeason();
        assertEq(deployed.balanceOf(address(this)), SUPPLY);
    }

    function test_factoryReceivesSupplyRatherThanTransactionCaller() public {
        TokenFactoryProbe factory = new TokenFactoryProbe();
        vm.prank(alice);
        FarmingSeason deployed = factory.deploy();
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(alice), 0);
        assertEq(deployed.balanceOf(address(this)), 0);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_transferEmitsEventAndDeliversExactAmount() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 25 ether);
        assertTrue(token.transfer(alice, 25 ether));
        assertEq(token.balanceOf(alice), 25 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 25 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_entireSupplyCanMoveAndReturn() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_zeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_selfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferToZeroRevertsEvenForZeroAmount() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferAboveBalanceRevertsWithoutMovingTokens() public {
        token.transfer(alice, 3 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 3 ether, 3 ether + 1)
        );
        vm.prank(alice);
        token.transfer(bob, 3 ether + 1);
        assertEq(token.balanceOf(alice), 3 ether);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_maximumUintTransferRevertsWithoutOverflow() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_approveEmitsEventWithoutMovingBalance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Approval(address(this), spender, 42 ether);
        assertTrue(token.approve(spender, 42 ether));
        assertEq(token.allowance(address(this), spender), 42 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_approvalCanBeReplacedAndRevoked() public {
        token.approve(spender, 100);
        token.approve(spender, 200);
        assertEq(token.allowance(address(this), spender), 200);
        token.approve(spender, 10);
        assertEq(token.allowance(address(this), spender), 10);
        token.approve(spender, 0);
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
    }

    function test_approveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
    }

    function test_transferFromConsumesFiniteAllowanceAndEmitsTransfer() public {
        token.approve(spender, 100 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(address(this), alice, 40 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 40 ether));
        assertEq(token.allowance(address(this), spender), 60 ether);
        assertEq(token.balanceOf(alice), 40 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 40 ether);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromCanSpendExactAllowanceOnce() public {
        token.approve(spender, 1 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1 ether));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 1 ether);
    }

    function test_transferFromAboveAllowanceReverts() public {
        token.approve(spender, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 10, 11));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 11);
        assertEq(token.allowance(address(this), spender), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_deployerCannotSpendHolderTokensWithoutApproval() public {
        token.transfer(alice, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, bob, 1);
        assertEq(token.balanceOf(alice), 1 ether);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_allowanceForOneSpenderDoesNotAuthorizeAnother() public {
        token.approve(spender, SUPPLY);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_transferFromZeroAmountNeedsNoAllowance() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit Transfer(alice, bob, 0);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromZeroSenderReverts() public {
        // OpenZeppelin validates the allowance owner before reaching the transfer.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(0), alice, 0);
    }

    function test_invalidRecipientRestoresSpentAllowance() public {
        token.approve(spender, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 5);
        assertEq(token.allowance(address(this), spender), 10);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_insufficientBalanceRestoresSpentAllowance() public {
        vm.prank(alice);
        token.approve(spender, 10);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 5));
        vm.prank(spender);
        token.transferFrom(alice, bob, 5);
        assertEq(token.allowance(alice, spender), 10);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_infiniteAllowanceIsNotDecremented() public {
        token.approve(spender, type(uint256).max);
        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1 ether));
        assertTrue(token.transferFrom(address(this), bob, 2 ether));
        vm.stopPrank();
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 1 ether);
        assertEq(token.balanceOf(bob), 2 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferFromToSelfConsumesAllowanceButPreservesBalance() public {
        token.approve(spender, 10);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), 7));
        assertEq(token.allowance(address(this), spender), 3);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_transferFromOwnAccountStillRequiresAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_noMintBurnOrAdministrativeEntryPoints() public {
        token.transfer(alice, 1 ether);
        bytes[] memory calls = new bytes[](8);
        calls[0] = abi.encodeWithSignature("mint(address,uint256)", bob, SUPPLY);
        calls[1] = abi.encodeWithSignature("burn(uint256)", 1 ether);
        calls[2] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1 ether);
        calls[3] = abi.encodeWithSignature("pause()");
        calls[4] = abi.encodeWithSignature("blacklist(address)", alice);
        calls[5] = abi.encodeWithSignature("initialize(address)", bob);
        calls[6] = abi.encodeWithSignature("upgradeTo(address)", bob);
        calls[7] = abi.encodeWithSignature("transferOwnership(address)", bob);
        for (uint256 i; i < calls.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(calls[i]);
            assertFalse(deployerSucceeded);
            vm.prank(bob);
            (bool strangerSucceeded,) = address(token).call(calls[i]);
            assertFalse(strangerSucceeded);
        }
        vm.warp(block.timestamp + 365 days);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 1 ether));
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(bob), 1 ether);
    }

    function test_directEtherPaymentReverts() public {
        vm.deal(address(this), 1 ether);
        (bool success,) = address(token).call{value: 1 ether}("");
        assertFalse(success);
        assertEq(address(token).balance, 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferConservesSupply(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.balanceOf(recipient) + token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferFromConservesSupplyAndConsumesAllowance(uint256 amount, uint256 approval) public {
        amount = bound(amount, 0, SUPPLY);
        approval = bound(approval, amount, type(uint256).max - 1);
        token.approve(spender, approval);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertEq(token.allowance(address(this), spender), approval - amount);
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveBalanceAlwaysReverts(uint256 amount) public {
        amount = bound(amount, SUPPLY + 1, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, amount)
        );
        token.transfer(alice, amount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_transferAboveAllowanceAlwaysReverts(uint256 allowanceAmount, uint256 excess) public {
        allowanceAmount = bound(allowanceAmount, 0, SUPPLY - 1);
        excess = bound(excess, 1, SUPPLY - allowanceAmount);
        token.approve(spender, allowanceAmount);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowanceAmount, allowanceAmount + excess
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, allowanceAmount + excess);
        assertEq(token.allowance(address(this), spender), allowanceAmount);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }
}
