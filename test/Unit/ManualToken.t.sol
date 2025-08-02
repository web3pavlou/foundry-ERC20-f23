// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, Vm} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {ManualToken} from "src/ManualToken.sol";

/*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
error ManualToken__InsufficientBalance();
error ManualToken__SpenderHasNoCode();

/// @dev Minimal approval-recipient used to test `approveAndCall`.
contract ApprovalSink {
    event GotApproval(address indexed sender, uint256 value, address token);

    function receiveApproval(
        address from,
        uint256 value,
        address token,
        bytes calldata /*extra*/
    ) external {
        emit GotApproval(from, value, token);

        // Spend half the allowance immediately – exercises re-entrancy window.
        ManualToken(token).transferFrom(from, address(this), value / 2);
    }
}

contract ManualTokenTest is Test {
    uint256 private constant INITIAL_SUPPLY_TOKENS = 1_000_000; // whole tokens

    ManualToken internal token;
    ApprovalSink internal sink;
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        token = new ManualToken(INITIAL_SUPPLY_TOKENS, "ManualToken", "MTK");
        sink = new ApprovalSink();

        // Give Alice some tokens
        token.transfer(alice, 1000 ether);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   UNIT TESTS
    //////////////////////////////////////////////////////////////////////////*/

    function units(uint256 tokens) internal pure returns (uint256) {
        return tokens * 1e18; // matches DECIMALS = 18
    }

    function testSymbolAndDecimals() public view {
        assertEq(token.symbol(), "MTK");
        assertEq(token.decimals(), 18);
    }

    function testTransferUpdatesBalances() public {
        uint256 amount = 250 ether;

        vm.prank(alice);
        token.transfer(bob, amount);

        assertEq(token.balanceOf(alice), 750 ether, "Alice balance wrong");
        assertEq(token.balanceOf(bob), amount, "Bob balance wrong");
    }

    function testRevertWhenTransferInsufficientBalance() public {
        vm.prank(bob);
        vm.expectRevert(ManualToken__InsufficientBalance.selector);
        token.transfer(alice, 1 ether);
    }

    function testApproveAndCallSpenderMustHaveCode() public {
        vm.prank(alice);
        vm.expectRevert(ManualToken__SpenderHasNoCode.selector);
        token.approveAndCall(bob, 1 ether, "");
    }

    function testApproveAndCallSucceedsAndCallbackSpends() public {
        uint256 allowanceAmt = 100 ether;

        vm.prank(alice);
        token.approveAndCall(address(sink), allowanceAmt, "0x");

        // Sink spends half inside callback, half remains
        assertEq(token.balanceOf(address(sink)), allowanceAmt / 2);
        assertEq(
            token.allowance(alice, address(sink)),
            allowanceAmt / 2,
            "allowance should shrink"
        );
    }

    /* ------------------- burn / burnFrom ---------------------------------- */

    function testBurnReducesSupplyAndBalance() public {
        uint256 burnAmt = 10 ether;

        vm.prank(alice);
        token.burn(burnAmt);

        assertEq(
            token.totalSupply(),
            units(INITIAL_SUPPLY_TOKENS) - burnAmt,
            "supply mismatch"
        );
        assertEq(token.balanceOf(alice), 990 ether);
    }

    function testBurnFromWithFiniteAllowance() public {
        uint256 burnAmt = 20 ether;

        vm.startPrank(alice);
        token.approve(bob, burnAmt);
        vm.stopPrank();

        vm.prank(bob);
        token.burnFrom(alice, burnAmt);

        assertEq(token.balanceOf(alice), 980 ether);
        assertEq(token.allowance(alice, bob), 0);
    }

    function testBurnFromWithInfiniteAllowanceGasOptimized() public {
        uint256 burnAmt = 5 ether;

        vm.startPrank(alice);
        token.approve(bob, type(uint256).max);
        vm.stopPrank();

        vm.prank(bob);
        token.burnFrom(alice, burnAmt);

        // Allowance should stay max (storage slot untouched)
        assertEq(token.allowance(alice, bob), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                   FUZZ TESTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Fuzz transfer invariants: balances never underflow.
    function testFuzzTransferHonorsBalance(uint96 amount) public {
        amount = uint96(bound(amount, 1, 1000 ether));

        vm.assume(amount <= token.balanceOf(alice));

        vm.prank(alice);
        token.transfer(bob, amount);

        assertEq(
            token.balanceOf(alice) + token.balanceOf(bob),
            1000 ether,
            "conservation failed"
        );
    }

    /// @dev Fuzz approve/transferFrom path with bounded amounts
    function testFuzzTransferFrom(uint128 approveAmt, uint128 spend) public {
        approveAmt = uint128(bound(approveAmt, 1, 500 ether));
        spend = uint128(bound(spend, 1, approveAmt));

        vm.startPrank(alice);
        token.approve(bob, approveAmt);
        vm.stopPrank();

        vm.prank(bob);
        token.transferFrom(alice, bob, spend);

        assertEq(token.balanceOf(bob), spend);
        assertEq(token.allowance(alice, bob), approveAmt - spend);
    }
}
