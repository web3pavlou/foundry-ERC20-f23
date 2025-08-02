// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test, Vm} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DeployManualToken} from "script/DeployManualToken.s.sol";
import {ManualToken} from "src/ManualToken.sol";

error ManualToken__InsufficientAllowance();
error ManualToken__SpenderHasNoCode();

contract ManualTokenStagingTest is Test {
    /*//////////////////////////////////////////////////////////////
                                 CONSTANTS
    //////////////////////////////////////////////////////////////*/
    uint256 internal constant INITIAL_SUPPLY_TOKENS = 1_000; // must match script
    uint256 internal constant SEPOLIA_CHAIN_ID = 11155111;
    bytes32 internal constant TRANSFER_SIG =
        keccak256("Transfer(address,address,uint256)");

    /*//////////////////////////////////////////////////////////////
                              STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    DeployManualToken private deployManualToken;
    ManualToken private token;
    address private deployer; // discovered from constructor mint

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    /// @dev Soft-skip unless running on a Sepolia fork (or Sepolia itself).
    modifier onSepoliaOrSkip() {
        if (block.chainid != SEPOLIA_CHAIN_ID) {
            // Not on Sepolia: skip quietly
            return;
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                  SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() external onSepoliaOrSkip {
        // 1) Run the deployment script in the active fork and capture logs
        deployManualToken = new DeployManualToken();

        vm.recordLogs();
        token = deployManualToken.run(); // broadcast uses default or env PRIVATE_KEY

        // 2) Parse the Transfer(0x0 -> deployer, amount) mint from constructor
        Vm.Log[] memory entries = vm.getRecordedLogs();
        for (uint256 i; i < entries.length; ++i) {
            if (
                entries[i].emitter == address(token) &&
                entries[i].topics.length == 3 &&
                entries[i].topics[0] == TRANSFER_SIG &&
                entries[i].topics[1] == bytes32(0) // from == address(0)
            ) {
                deployer = address(uint160(uint256(entries[i].topics[2]))); // to
                break;
            }
        }
        require(deployer != address(0), "mint event not found");

        vm.label(deployer, "deployer");
        vm.label(address(token), "ManualToken");
    }

    /*//////////////////////////////////////////////////////////////
                                STAGING CHECKS
    //////////////////////////////////////////////////////////////*/

    function testDeployment_MintsInitialSupply() external view onSepoliaOrSkip {
        uint8 decimals = token.decimals();
        uint256 expectedSupply = INITIAL_SUPPLY_TOKENS *
            (10 ** uint256(decimals));

        assertEq(token.totalSupply(), expectedSupply, "totalSupply mismatch");
        assertEq(
            token.balanceOf(deployer),
            expectedSupply,
            "deployer balance mismatch"
        );
        assertEq(token.name(), "ManualToken", "name mismatch");
        assertEq(token.symbol(), "MTK", "symbol mismatch");
    }

    function testAllowanceAndTransferFlow() external onSepoliaOrSkip {
        address spender = makeAddr("spender");

        // Grant allowance
        vm.prank(deployer);
        token.approve(spender, 5 ether);
        assertEq(
            token.allowance(deployer, spender),
            5 ether,
            "allowance grant failed"
        );

        // Spend part of allowance
        vm.prank(spender);
        token.transferFrom(deployer, spender, 2 ether);

        assertEq(token.balanceOf(spender), 2 ether, "transferFrom failed");
        assertEq(
            token.allowance(deployer, spender),
            3 ether,
            "allowance not reduced"
        );
    }

    function test_RevertWhen_AllowanceTooLow() external onSepoliaOrSkip {
        address spender = makeAddr("spender");

        vm.prank(deployer);
        token.approve(spender, 1 ether);

        vm.prank(spender);
        vm.expectRevert(ManualToken__InsufficientAllowance.selector);
        token.transferFrom(deployer, spender, 2 ether);
    }

    function test_RevertWhen_ApproveAndCallToEOA() external onSepoliaOrSkip {
        address eoaSpender = makeAddr("eoa-spender");
        vm.prank(deployer);
        vm.expectRevert(ManualToken__SpenderHasNoCode.selector);
        token.approveAndCall(eoaSpender, 1 ether, "");
    }
}
