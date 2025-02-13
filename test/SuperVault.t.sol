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

        // No necesitamos verificar el strategy address de Aave ya que ahora es un pool
        assertEq(
            vault.getPoolAddress("AAVE"),
            address(aavePool),
            "Aave pool should be set correctly"
        );
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

    function test_DepositToAavePool() public {
        uint256 depositAmount = 100 * 10 ** 18;
        uint256 allocateAmount = 50 * 10 ** 18;

        // First deposit into vault
        vm.startPrank(user);
        vault.deposit(depositAmount);
        vm.stopPrank();

        // Then deposit to Aave pool
        vm.startPrank(agent);
        vault.depositToPool("AAVE", allocateAmount);
        vm.stopPrank();

        // Verify balances
        assertEq(
            asset.balanceOf(address(vault)),
            depositAmount - allocateAmount,
            "Vault balance should be reduced by allocated amount"
        );
        assertEq(
            vault.getPoolBalance("AAVE", address(asset)),
            allocateAmount,
            "Pool deposits should be tracked correctly"
        );
    }

    function test_WithdrawFromAavePool() public {
        uint256 depositAmount = 100 * 10 ** 18;
        uint256 allocateAmount = 50 * 10 ** 18;
        uint256 withdrawAmount = 25 * 10 ** 18;

        // Setup: deposit and allocate
        vm.startPrank(user);
        vault.deposit(depositAmount);
        vm.stopPrank();

        vm.startPrank(agent);
        vault.depositToPool("AAVE", allocateAmount);

        // Withdraw from Aave pool
        vault.withdrawFromPool("AAVE", withdrawAmount);
        vm.stopPrank();

        // Verify balances after withdrawal
        assertEq(
            vault.getPoolBalance("AAVE", address(asset)),
            allocateAmount - withdrawAmount,
            "Pool balance should be reduced by withdrawn amount"
        );
        assertEq(
            asset.balanceOf(address(vault)),
            depositAmount - allocateAmount + withdrawAmount,
            "Vault should receive withdrawn amount"
        );
    }

    function test_RevertOnExcessiveWithdrawFromPool() public {
        uint256 depositAmount = 100 * 10 ** 18;
        uint256 allocateAmount = 50 * 10 ** 18;
        uint256 excessiveWithdrawAmount = 75 * 10 ** 18;

        // Setup: deposit and allocate
        vm.startPrank(user);
        vault.deposit(depositAmount);
        vm.stopPrank();

        vm.startPrank(agent);
        vault.depositToPool("AAVE", allocateAmount);

        // Try to withdraw more than allocated
        vm.expectRevert("SuperVault: insufficient pool balance");
        vault.withdrawFromPool("AAVE", excessiveWithdrawAmount);
        vm.stopPrank();
    }

    function test_OnlyAgentCanDepositToPool() public {
        uint256 depositAmount = 100 * 10 ** 18;
        uint256 allocateAmount = 50 * 10 ** 18;

        // First deposit into vault
        vm.startPrank(user);
        vault.deposit(depositAmount);

        // Try to deposit as regular user
        vm.expectRevert("SuperVault: agent only");
        vault.depositToPool("AAVE", allocateAmount);
        vm.stopPrank();
    }

    function test_AddNewPool() public {
        address newPoolAddress = makeAddr("newPool");

        vm.startPrank(admin);
        vault.addPool("NEW_POOL", newPoolAddress);
        vm.stopPrank();

        assertEq(
            vault.getPoolAddress("NEW_POOL"),
            newPoolAddress,
            "New pool should be added correctly"
        );
        assertTrue(
            vault.getPoolList().length > 0,
            "Pool list should not be empty"
        );
    }

    function test_OnlyAdminCanAddPool() public {
        address newPoolAddress = makeAddr("newPool");

        vm.startPrank(user);
        vm.expectRevert("SuperVault: admin only");
        vault.addPool("NEW_POOL", newPoolAddress);
        vm.stopPrank();
    }

    function test_CannotAddDuplicatePool() public {
        vm.startPrank(admin);
        vm.expectRevert("SuperVault: pool already exists");
        vault.addPool("AAVE", address(aavePool));
        vm.stopPrank();
    }

    function test_CannotAddPoolWithEmptyName() public {
        vm.startPrank(admin);
        vm.expectRevert("SuperVault: empty pool name");
        vault.addPool("", address(aavePool));
        vm.stopPrank();
    }

    function test_CannotAddPoolWithZeroAddress() public {
        vm.startPrank(admin);
        vm.expectRevert("SuperVault: zero pool address");
        vault.addPool("NEW_POOL", address(0));
        vm.stopPrank();
    }

    function test_GetPoolList() public {
        string[] memory pools = vault.getPoolList();
        assertEq(pools.length, 1, "Should have one pool initially");
        assertEq(pools[0], "AAVE", "First pool should be AAVE");
    }
}
