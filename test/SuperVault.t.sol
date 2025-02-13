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
import {IAsset} from "../src/interfaces/IAsset.sol";

// Definición de la interfaz IBalancerV2 con los structs mínimos necesarios
interface IBalancerV2 {
    struct JoinPoolRequest {
        IAsset[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }
    struct ExitPoolRequest {
        IAsset[] assets;
        uint256[] minAmountsOut;
        bytes userData;
        bool toInternalBalance;
    }

    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest memory request
    ) external;

    function exitPool(
        bytes32 poolId,
        address sender,
        address recipient,
        ExitPoolRequest memory request
    ) external;
}

// Implementación mock de BalancerV2
contract BalancerV2Mock is IBalancerV2 {
    event JoinedPool(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] maxAmountsIn
    );
    event ExitedPool(
        bytes32 poolId,
        address sender,
        address recipient,
        uint256[] minAmountsOut
    );

    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest memory request
    ) external override {
        emit JoinedPool(poolId, sender, recipient, request.maxAmountsIn);
    }

    function exitPool(
        bytes32 poolId,
        address sender,
        address recipient,
        ExitPoolRequest memory request
    ) external override {
        emit ExitedPool(poolId, sender, recipient, request.minAmountsOut);
    }
}

contract MockToken is ERC20 {
    constructor() ERC20("Mock Token", "MTK") {
        _mint(msg.sender, 1000000 * 10 ** decimals());
    }
}

// Declaramos los eventos de liquidez para testearlos
// Estos eventos tienen la misma firma que en BalancerStrategy.sol
// event LiquidityAdded(bytes32 indexed poolId, uint256[] amounts);
// event LiquidityRemoved(bytes32 indexed poolId, uint256[] amounts);

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

    // Declaramos los eventos para testear las acciones de liquidez
    event LiquidityAdded(bytes32 indexed poolId, uint256[] amounts);
    event LiquidityRemoved(bytes32 indexed poolId, uint256[] amounts);

    function setUp() public {
        // Configuración de cuentas
        admin = makeAddr("admin");
        agent = makeAddr("agent");
        user = makeAddr("user");

        // Desplegamos el mock de Balancer vault
        BalancerV2Mock balancerMock = new BalancerV2Mock();
        balancerVault = address(balancerMock);

        // Desplegamos tokens mock
        token = new MockToken();
        asset = new MockToken();

        // Desplegamos el mock de Aave pool
        aavePool = new AaveV3Mock();

        // Desplegamos el vault
        vault = new SuperVault(
            admin,
            IERC20(address(asset)),
            "Vault Token",
            "vTKN",
            agent,
            address(aavePool),
            balancerVault
        );

        // Configuramos balances iniciales
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

    function test_Withdraw() public {
        uint256 depositAmount = 100 * 10 ** 18;
        uint256 expectedShares = vault.previewDeposit(depositAmount);
        vm.startPrank(user);

        vault.deposit(depositAmount);
        assertEq(asset.balanceOf(address(vault)), depositAmount);
        vm.stopPrank();
        vm.startPrank(user);
        vault.withdraw(expectedShares);
        assertEq(asset.balanceOf(user), INITIAL_BALANCE);
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

        // Get Aave strategy address
        address aaveStrategy = vault.getStrategyAddress(
            DataTypes.StrategyType.AAVE
        );

        // Verify balances
        assertEq(
            asset.balanceOf(address(vault)),
            depositAmount - allocateAmount,
            "Vault balance should be reduced by allocated amount"
        );
        assertEq(
            aavePool.getUserBalance(address(asset), aaveStrategy),
            allocateAmount,
            "Aave pool should have received the allocated amount"
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

        // Withdraw from Aave strategy
        vault.withdrawFromStrategy(DataTypes.StrategyType.AAVE, withdrawAmount);
        vm.stopPrank();

        address aaveStrategy = vault.getStrategyAddress(
            DataTypes.StrategyType.AAVE
        );

        // Verify balances after withdrawal
        assertEq(
            aavePool.getUserBalance(address(asset), aaveStrategy),
            allocateAmount - withdrawAmount,
            "Aave pool balance should be reduced by withdrawn amount"
        );
        assertEq(
            asset.balanceOf(address(vault)),
            depositAmount - allocateAmount + withdrawAmount,
            "Vault should receive withdrawn amount"
        );
    }

    function test_RevertOnExcessiveWithdrawFromAave() public {
        uint256 depositAmount = 100 * 10 ** 18;
        uint256 allocateAmount = 50 * 10 ** 18;
        uint256 excessiveWithdrawAmount = 75 * 10 ** 18;

        // Setup: deposit and allocate
        vm.startPrank(user);
        vault.deposit(depositAmount);
        vm.stopPrank();

        vm.startPrank(agent);
        vault.allocateToStrategy(DataTypes.StrategyType.AAVE, allocateAmount);

        // Try to withdraw more than allocated
        vm.expectRevert("AaveStrategy: insufficient balance");
        vault.withdrawFromStrategy(
            DataTypes.StrategyType.AAVE,
            excessiveWithdrawAmount
        );
        vm.stopPrank();
    }

    function test_OnlyAgentCanAllocateToAave() public {
        uint256 depositAmount = 100 * 10 ** 18;
        uint256 allocateAmount = 50 * 10 ** 18;

        // First deposit into vault
        vm.startPrank(user);
        vault.deposit(depositAmount);

        // Try to allocate as regular user
        vm.expectRevert("SuperVault: agent only");
        vault.allocateToStrategy(DataTypes.StrategyType.AAVE, allocateAmount);
        vm.stopPrank();
    }

    function test_AllocateZeroAmountToAave() public {
        uint256 depositAmount = 100 * 10 ** 18;

        // Setup: deposit
        vm.startPrank(user);
        vault.deposit(depositAmount);
        vm.stopPrank();

        // Try to allocate zero amount
        vm.startPrank(agent);
        vm.expectRevert("SuperVault: zero amount");
        vault.allocateToStrategy(DataTypes.StrategyType.AAVE, 0);
        vm.stopPrank();
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

    // function test_AddAndRemoveLiquidity() public {
    //     // Para testear acciones de liquidez en Balancer
    //     uint256 depositAmount = 200 * 10 ** 18;
    //     // Depositar en el vault primero
    //     vm.startPrank(user);
    //     vault.deposit(depositAmount);
    //     vm.stopPrank();

    //     // Parámetros para añadir/quitar liquidez
    //     bytes32 poolId = bytes32("pool1");
    //     IAsset[] memory assets = new IAsset[](1);
    //     assets[0] = IAsset(address(asset));
    //     uint256[] memory amounts = new uint256[](1);
    //     amounts[0] = 50 * 10 ** 18;
    //     bytes memory userData = "";

    //     // Esperamos el evento LiquidityAdded desde BalancerStrategy
    //     vm.startPrank(agent);
    //     vm.expectEmit(true, false, false, true);
    //     emit LiquidityAdded(poolId, amounts);
    //     vault.addLiquidityToBalancer(poolId, assets, amounts, userData);
    //     vm.stopPrank();

    //     // Esperamos el evento LiquidityRemoved desde BalancerStrategy
    //     vm.startPrank(agent);
    //     vm.expectEmit(true, false, false, true);
    //     emit LiquidityRemoved(poolId, amounts);
    //     vault.removeLiquidityFromBalancer(poolId, assets, amounts, userData);
    //     vm.stopPrank();
    // }
}
