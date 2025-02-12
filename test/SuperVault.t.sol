// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {SuperVault} from "../src/SuperVault.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DataTypes} from "../src/libraries/DataTypes.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {AaveV3Mock} from "./mocks/AaveV3Mock.sol";

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
    AaveV3Mock public aavePool;
    address public balancerVault;

    address public admin;
    address public agent;
    address public user;

    uint256 constant INITIAL_BALANCE = 1000 * 10 ** 18;

    function setUp() public {
        // Setup accounts
        admin = makeAddr("admin");
        agent = makeAddr("agent");
        user = makeAddr("user");
        balancerVault = makeAddr("balancerVault");

        // Deploy mock tokens
        token = new MockToken();
        asset = new MockToken();

        // Deploy mock Aave pool
        aavePool = new AaveV3Mock();

        // Deploy vault
        vault = new SuperVault(
            admin,
            IERC20(address(asset)),
            "Vault Token",
            "vTKN",
            agent,
            address(aavePool),
            balancerVault
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
        vault.deposit(depositAmount);

        assertEq(vault.balanceOf(user), expectedShares);
        assertEq(asset.balanceOf(address(vault)), depositAmount);
        assertEq(asset.balanceOf(user), INITIAL_BALANCE - depositAmount);
        vm.stopPrank();
    }

    function test_AllocateToAave() public {
        uint256 depositAmount = 100 * 10 ** 18;
        uint256 allocateAmount = 50 * 10 ** 18;

        // First deposit into vault
        vm.startPrank(user);
        vault.deposit(depositAmount);
        vm.stopPrank();

        // Then allocate to Aave strategy
        vm.startPrank(agent);
        vault.allocateToStrategy(DataTypes.StrategyType.AAVE, allocateAmount);
        vm.stopPrank();

        address aaveStrategy = vault.getStrategyAddress(
            DataTypes.StrategyType.AAVE
        );
        assertEq(asset.balanceOf(aaveStrategy), allocateAmount);
        assertEq(
            asset.balanceOf(address(vault)),
            depositAmount - allocateAmount
        );
    }

    function test_WithdrawFromAave() public {
        uint256 depositAmount = 100 * 10 ** 18;
        uint256 allocateAmount = 50 * 10 ** 18;
        uint256 withdrawAmount = 25 * 10 ** 18;

        // Setup: deposit and allocate
        vm.startPrank(user);
        vault.deposit(depositAmount);
        vm.stopPrank();

        vm.startPrank(agent);
        vault.allocateToStrategy(DataTypes.StrategyType.AAVE, allocateAmount);

        // Test withdrawal
        vault.withdrawFromStrategy(DataTypes.StrategyType.AAVE, withdrawAmount);
        vm.stopPrank();

        address aaveStrategy = vault.getStrategyAddress(
            DataTypes.StrategyType.AAVE
        );
        assertEq(
            asset.balanceOf(aaveStrategy),
            allocateAmount - withdrawAmount
        );
        assertEq(
            asset.balanceOf(address(vault)),
            depositAmount - allocateAmount + withdrawAmount
        );
    }

    function test_RevertOnExcessiveAllocation() public {
        uint256 depositAmount = 100 * 10 ** 18;
        uint256 allocateAmount = 150 * 10 ** 18;

        vm.startPrank(user);
        vault.deposit(depositAmount);
        vm.stopPrank();

        vm.startPrank(agent);
        vm.expectRevert("SuperVault: insufficient balance");
        vault.allocateToStrategy(DataTypes.StrategyType.AAVE, allocateAmount);
        vm.stopPrank();
    }
}
