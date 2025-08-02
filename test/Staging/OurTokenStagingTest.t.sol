// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DeployOurToken} from "script/DeployOurToken.s.sol";
import {OurToken} from "src/OurToken.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract OurTokenStagingTest is Test {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error OurTokenStagingTest__MintEventNotFound();

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/
    uint256 internal constant INITIAL_SUPPLY = 1_000 ether;
    uint256 internal constant SEPOLIA_CHAIN_ID = 11155111;
    bytes32 internal constant TRANSFER_SIG =
        keccak256("Transfer(address,address,uint256)");

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    DeployOurToken private deployOurToken;
    ERC20 private ourToken; // OZ v5 core ERC20 (no inc/dec helpers)
    address private deployer; // discovered from constructor mint

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    /// @dev Soft-skip unless running on a Sepolia fork.
    modifier onSepoliaOrSkip() {
        if (block.chainid != SEPOLIA_CHAIN_ID) {
            return; // skip on non-Sepolia chains
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                  SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() external onSepoliaOrSkip {
        // 1. Run your deployment script inside the active Sepolia fork
        deployOurToken = new DeployOurToken();

        // 2. Detect constructor mint to find `deployer`
        vm.recordLogs();
        OurToken deployed = deployOurToken.run();
        ourToken = ERC20(address(deployed));

        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i; i < entries.length; ++i) {
            if (
                entries[i].emitter == address(ourToken) &&
                entries[i].topics.length == 3 &&
                entries[i].topics[0] == TRANSFER_SIG &&
                entries[i].topics[1] == bytes32(0) // from == address(0)
            ) {
                deployer = address(uint160(uint256(entries[i].topics[2]))); // to
                break;
            }
        }
        if (deployer == address(0))
            revert OurTokenStagingTest__MintEventNotFound();

        vm.label(deployer, "deployer");
        vm.label(address(ourToken), "OurToken");
    }

    /* ---------------- Staging checks (no unit duplication) ----------------- */

    function testDeploymentMintsInitialSupply() external view onSepoliaOrSkip {
        assertEq(
            ourToken.totalSupply(),
            INITIAL_SUPPLY,
            "totalSupply mismatch"
        );
        assertEq(
            ourToken.balanceOf(deployer),
            INITIAL_SUPPLY,
            "deployer balance"
        );
        assertEq(ourToken.name(), "OurToken", "name");
        assertEq(ourToken.symbol(), "OT", "symbol");
    }

    function testAllowanceAndTransferFlow() external onSepoliaOrSkip {
        address spender = makeAddr("spender");

        // Deployer sets fresh allowance via approve
        vm.prank(deployer);
        ourToken.approve(spender, 5 ether);
        assertEq(
            ourToken.allowance(deployer, spender),
            5 ether,
            "allowance grant failed"
        );

        // Spender pulls part of the allowance
        vm.startPrank(spender);
        ourToken.transferFrom(deployer, spender, 2 ether);
        vm.stopPrank();

        assertEq(ourToken.balanceOf(spender), 2 ether, "transferFrom failed");
        assertEq(
            ourToken.allowance(deployer, spender),
            3 ether,
            "allowance not reduced"
        );
    }

    function testRevertWhenAllowanceTooLow() external onSepoliaOrSkip {
        address spender = makeAddr("spender");

        // Allow only 1 ether
        vm.prank(deployer);
        ourToken.approve(spender, 1 ether);

        // Spender tries to pull 2 ether → expect OZ v5 custom error
        vm.prank(spender);
        vm.expectRevert(); // ERC20InsufficientAllowance(...)
        ourToken.transferFrom(deployer, spender, 2 ether);
    }
}
