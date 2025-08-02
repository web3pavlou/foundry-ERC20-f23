// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {DeployOurToken} from "../../script/DeployOurToken.s.sol";
import {OurToken} from "../../src/OurToken.sol";
import {Test, console2} from "forge-std/Test.sol";
import {ZkSyncChainChecker} from "lib/foundry-devops/src/ZkSyncChainChecker.sol";

interface MintableToken {
    function mint(address, uint256) external;
}

contract OurTokenTest is Test, ZkSyncChainChecker {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/
    uint256 internal BOB_STARTING_AMOUNT = 100 ether;
    uint256 public constant INITIAL_SUPPLY = 1_000_000 ether; // 1 million tokens with 18 decimals

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    OurToken internal ourToken;
    DeployOurToken internal deployer;

    address internal bob;
    address internal alice;
    address internal evan;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed sender,
        uint256 value
    );

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() public {
        deployer = new DeployOurToken();

        if (!isZkSyncChain()) {
            ourToken = deployer.run();
        } else {
            // Local zkSync: deploy directly
            ourToken = new OurToken(INITIAL_SUPPLY);
            // msg.sender during setUp() is this test contract; this transfer is a no-op but explicit.
            ourToken.transfer(msg.sender, INITIAL_SUPPLY);
        }

        bob = makeAddr("bob");
        alice = makeAddr("alice");
        evan = makeAddr("evan");

        // Seed Bob with tokens from the deployer/test contract holder.
        vm.prank(msg.sender);
        ourToken.transfer(bob, BOB_STARTING_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/
    function testExpectedInitialSupply() internal returns (uint256) {
        return isZkSyncChain() ? INITIAL_SUPPLY : deployer.INITIAL_SUPPLY();
    }

    /*//////////////////////////////////////////////////////////////
                                METADATA
    //////////////////////////////////////////////////////////////*/
    function testMetadataAreCorrect() public view {
        assertEq(ourToken.name(), "OurToken", "name mismatch");
        assertEq(ourToken.symbol(), "OT", "symbol mismatch");
        assertEq(ourToken.decimals(), 18, "decimals mismatch");
    }

    function testTotalSupplyEqualsInitialSupply() public {
        assertEq(
            ourToken.totalSupply(),
            testExpectedInitialSupply(),
            "unexpected totalSupply"
        );
    }

    /*//////////////////////////////////////////////////////////////
                         NON-MINTABLE / ACCESS
    //////////////////////////////////////////////////////////////*/
    function testRevertsWhenNonOwnerMints() public {
        vm.expectRevert();
        MintableToken(address(ourToken)).mint(address(this), 1);
    }

    /*//////////////////////////////////////////////////////////////
                              TRANSFERS
    //////////////////////////////////////////////////////////////*/
    function testTransferSucceedsAndEmitsAnEvent() public {
        uint256 amount = 10 ether;

        vm.prank(bob);
        vm.expectEmit(true, true, false, true);
        emit Transfer(bob, alice, amount);
        bool success = ourToken.transfer(alice, amount);

        assertTrue(success, "transfer was unsuccessful");
        assertEq(
            ourToken.balanceOf(bob),
            BOB_STARTING_AMOUNT - amount,
            "bob balance is not enough"
        );
        assertEq(ourToken.balanceOf(alice), amount, "alice balance is wrong");
    }

    function testTransferRevertsWhenHasInsufficientBalance() public {
        uint256 amount = BOB_STARTING_AMOUNT + 1;

        vm.prank(bob);
        vm.expectRevert();
        ourToken.transfer(alice, amount);
    }

    function testRevertsWhenTransferToZeroAddress() public {
        vm.prank(bob);
        vm.expectRevert();
        ourToken.transfer(address(0), 1);
    }

    function testSelfTransferNoNetChange() public {
        uint256 balanceBefore = ourToken.balanceOf(bob);
        uint256 totalSupplyBefore = ourToken.totalSupply();

        vm.prank(bob);
        ourToken.transfer(bob, 123);

        assertEq(
            ourToken.balanceOf(bob),
            balanceBefore,
            "Bob balance should not change"
        );
        assertEq(
            ourToken.totalSupply(),
            totalSupplyBefore,
            "Supply should not change"
        );
    }

    function testZeroAmountTransferEmitsEventNoBalanceChange() public {
        uint256 bobBefore = ourToken.balanceOf(bob);
        uint256 aliceBefore = ourToken.balanceOf(alice);

        vm.prank(bob);
        vm.expectEmit(true, true, false, true);
        emit Transfer(bob, alice, 0);
        ourToken.transfer(alice, 0);

        assertEq(ourToken.balanceOf(bob), bobBefore, "bob balance has changed");
        assertEq(
            ourToken.balanceOf(alice),
            aliceBefore,
            "alice balance has changed"
        );
    }

    /*//////////////////////////////////////////////////////////////
                               ALLOWANCES
    //////////////////////////////////////////////////////////////*/

    function testApproveSetsAllowanceAndEmitsAnEvent() public {
        uint256 initialAllowance = 1000;

        vm.prank(bob);
        vm.expectEmit(true, true, false, true);
        emit Approval(bob, alice, initialAllowance);
        bool success = ourToken.approve(alice, initialAllowance);

        assertTrue(success, "approve returned false");
        assertEq(ourToken.allowance(bob, alice), initialAllowance);
    }

    function testTransferFromSucceedsAndDecreasesAllowances() public {
        uint256 initialAllowance = 1000;
        uint256 transferAmount = 500;

        vm.prank(bob);
        ourToken.approve(alice, initialAllowance);

        vm.prank(alice);
        ourToken.transferFrom(bob, evan, transferAmount);

        assertEq(
            ourToken.balanceOf(bob),
            BOB_STARTING_AMOUNT - transferAmount,
            "bob balance is wrong"
        );
        assertEq(
            ourToken.balanceOf(evan),
            transferAmount,
            "evan balance is wrong"
        );
        assertEq(
            ourToken.allowance(bob, alice),
            initialAllowance - transferAmount,
            "allowance not decreased"
        );
    }

    function testRevertWhenTransferFromHasInsufficientAllowance() public {
        vm.prank(bob);
        ourToken.approve(alice, 10);

        vm.prank(alice);
        vm.expectRevert(); // OZ v5: ERC20InsufficientAllowance
        ourToken.transferFrom(bob, evan, 11);
    }

    function testRevertsWhenTransferFromToZeroAddress() public {
        vm.prank(bob);
        ourToken.approve(alice, 10);

        vm.prank(alice);
        vm.expectRevert();
        ourToken.transferFrom(bob, address(0), 10);
    }

    function testInfiniteAllowanceDoesNotDecrease() public {
        vm.prank(bob);
        ourToken.approve(alice, type(uint256).max);

        vm.prank(alice);
        ourToken.transferFrom(bob, evan, 123);

        assertEq(ourToken.allowance(bob, alice), type(uint256).max);
    }

    /// Simulate "increase" by re-approving to a higher value; "decrease" by re-approving lower.
    function testApproveRaiseThenLower() public {
        vm.startPrank(bob);

        ourToken.approve(alice, 100);
        assertEq(ourToken.allowance(bob, alice), 100);

        // Increase via overwrite
        ourToken.approve(alice, 150);
        assertEq(ourToken.allowance(bob, alice), 150);

        // Decrease via overwrite
        ourToken.approve(alice, 101);
        assertEq(ourToken.allowance(bob, alice), 101);
        vm.stopPrank();

        // Prove insufficient allowance via transferFrom
        vm.expectRevert(); // OZ v5: ERC20InsufficientAllowance
        vm.prank(alice);
        ourToken.transferFrom(bob, evan, 102);

        vm.stopPrank();
    }

    function testapproveOverwriteExistingValue() public {
        vm.startPrank(bob);
        ourToken.approve(alice, 100);
        ourToken.approve(alice, 5);
        vm.stopPrank();

        assertEq(ourToken.allowance(bob, alice), 5);
    }

    /*//////////////////////////////////////////////////////////////
                                 FUZZ TESTING
    //////////////////////////////////////////////////////////////*/
    function testFuzzTranfer(uint96 amount, address to) public {
        vm.assume(to != address(0));
        vm.assume(to != bob);
        amount = uint96(bound(uint256(amount), 0, BOB_STARTING_AMOUNT));

        uint256 bobBefore = ourToken.balanceOf(bob);
        uint256 toBefore = ourToken.balanceOf(to);

        vm.prank(bob);
        bool success = ourToken.transfer(to, amount);
        assertTrue(success, "transfer was unsuccessful");

        assertEq(
            ourToken.balanceOf(bob),
            bobBefore - amount,
            "bob balance mismatch"
        );
        assertEq(
            ourToken.balanceOf(to),
            toBefore + amount,
            "to balance mismatch"
        );
    }

    function testFuzzApproveAndTransferFrom(
        uint96 approveAmount,
        uint96 spendAmount
    ) public {
        approveAmount = uint96(
            bound(uint256(approveAmount), 0, type(uint96).max)
        );
        spendAmount = uint96(bound(uint256(spendAmount), 0, approveAmount));
        spendAmount = uint96(
            bound(uint256(spendAmount), 0, BOB_STARTING_AMOUNT)
        );

        vm.prank(bob);
        ourToken.approve(alice, approveAmount);

        uint256 bobBefore = ourToken.balanceOf(bob);
        uint256 evanBefore = ourToken.balanceOf(evan);

        vm.prank(alice);
        ourToken.transferFrom(bob, evan, spendAmount);

        assertEq(
            ourToken.balanceOf(bob),
            bobBefore - spendAmount,
            "bob balance mismatch"
        );
        assertEq(
            ourToken.balanceOf(evan),
            evanBefore + spendAmount,
            "evan balance mismatch"
        );

        if (approveAmount == type(uint256).max) {
            assertEq(
                ourToken.allowance(bob, alice),
                type(uint256).max,
                "infinite allowance decreased"
            );
        } else {
            assertEq(
                ourToken.allowance(bob, alice),
                approveAmount - spendAmount,
                "allowance mismatch"
            );
        }
    }
}
