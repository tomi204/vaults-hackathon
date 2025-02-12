// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {SuperVault} from "../src/SuperVault.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Mock ERC20 token for testing
contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }
}

contract SuperVaultTest is Test {
    SuperVault public vault;
    MockToken public token;
    MockToken public asset;

    address public admin;
    address public agent;
    address public user;

    uint256 constant INITIAL_BALANCE = 1000 * 10 ** 18;

    function setUp() public {
        // Setup accounts
        admin = makeAddr("admin");
        agent = makeAddr("agent");
        user = makeAddr("user");

        // Deploy mock tokens
        token = new MockToken();
        asset = new MockToken();

        // Deploy vault
        vault = new SuperVault(
            address(token),
            admin,
            IERC20(address(asset)),
            "Vault Token",
            "vTKN",
            agent
        );

        // Setup initial balances
        asset.transfer(user, INITIAL_BALANCE);
        vm.startPrank(user);
        asset.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    function test_InitialState() public {
        assertEq(vault.name(), "Vault Token");
        assertEq(vault.symbol(), "vTKN");
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(vault.hasRole(vault.ADMIN_ROLE(), admin));
        assertTrue(vault.hasRole(vault.AGENT_ROLE(), agent));
    }

    function test_Deposit() public {
        uint256 depositAmount = 100 * 10 ** 18;

        vm.startPrank(user);
        uint256 expectedShares = vault.previewDeposit(depositAmount);
        // approve the vault to spend the user's assets
        asset.approve(address(vault), depositAmount);
        vault.deposit(depositAmount);
        // console.log("expectedShares", expectedShares);
        console.log("vault.balanceOf(user)", vault.balanceOf(user));
        assertEq(vault.balanceOf(user), expectedShares);
        assertEq(asset.balanceOf(address(vault)), depositAmount);
        assertEq(asset.balanceOf(user), INITIAL_BALANCE - depositAmount);
        vm.stopPrank();
    }

    function test_Withdraw() public {
        uint256 depositAmount = 100 * 10 ** 18;

        vm.startPrank(user);
        uint256 shares = vault.previewDeposit(depositAmount);
        vault.deposit(depositAmount);

        uint256 withdrawShares = shares / 2;
        uint256 expectedAssets = vault.previewRedeem(withdrawShares);
        vault.withdraw(withdrawShares, 0);

        assertEq(vault.balanceOf(user), shares - withdrawShares);
        assertEq(
            asset.balanceOf(address(vault)),
            depositAmount - expectedAssets
        );
        assertEq(
            asset.balanceOf(user),
            INITIAL_BALANCE - depositAmount + expectedAssets
        );
        vm.stopPrank();
    }

    function test_WithdrawAll() public {
        uint256 depositAmount = 100 * 10 ** 18;

        vm.startPrank(user);
        vault.deposit(depositAmount);
        uint256 shares = vault.balanceOf(user);
        vault.withdrawAll();

        assertEq(vault.balanceOf(user), 0);
        assertEq(asset.balanceOf(address(vault)), 0);
        assertEq(asset.balanceOf(user), INITIAL_BALANCE);
        vm.stopPrank();
    }

    function testFail_UnauthorizedAdminAction() public {
        vm.prank(user);
        vault.grantRole(vault.ADMIN_ROLE(), user);
    }

    function testFail_UnauthorizedAgentAction() public {
        vm.prank(user);
        vault.grantRole(vault.AGENT_ROLE(), user);
    }

    function test_AdminCanGrantRoles() public {
        address newAdmin = makeAddr("newAdmin");

        vm.startPrank(admin);
        vault.grantRole(vault.ADMIN_ROLE(), newAdmin);
        assertTrue(vault.hasRole(vault.ADMIN_ROLE(), newAdmin));
        vm.stopPrank();
    }

    function test_RevertOnInsufficientShares() public {
        uint256 depositAmount = 100 * 10 ** 18;

        vm.startPrank(user);
        vault.deposit(depositAmount);

        vm.expectRevert();
        vault.withdraw(depositAmount * 2, 0);
        vm.stopPrank();
    }

    function test_ShareToAssetConversion() public {
        uint256 depositAmount = 100 * 10 ** 18;

        vm.startPrank(user);
        uint256 shares = vault.previewDeposit(depositAmount);
        vault.deposit(depositAmount);

        uint256 assets = vault.convertToAssets(shares);
        assertEq(assets, depositAmount);
        vm.stopPrank();
    }
}
