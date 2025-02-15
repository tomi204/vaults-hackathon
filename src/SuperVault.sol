// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./interfaces/IAaveV3Pool.sol";
import "./interfaces/IBalancerV2.sol";
import "./interfaces/ILending.sol";
import "./libraries/DataTypes.sol";
import "./strategies/BalancerStrategy.sol";

/**
 * @title SuperVault
 * @dev A vault contract that manages multiple lending strategies and pools
 * This contract implements ERC4626 standard for tokenized vaults and includes
 * integration with Aave V3 and Balancer V2 protocols.
 */
contract SuperVault is ERC4626, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /**
     * @dev Structure to track lending pool information
     * @param poolAddress Address of the lending pool
     * @param isActive Status of the pool (active/inactive)
     * @param deposits Mapping of token address to deposit amount
     */
    struct LendingPool {
        address poolAddress;
        bool isActive;
        mapping(address => uint256) deposits;
    }

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");

    DataTypes.VaultInfo private vaultInfo;

    // Mapping to store strategy addresses by type
    mapping(DataTypes.StrategyType => address) public strategies;

    // Mapping to store multiple lending pools
    mapping(string => LendingPool) public lendingPools;
    string[] public poolList;

    event StrategyDeployed(
        DataTypes.StrategyType indexed strategyType,
        address strategyAddress
    );
    event FundsAllocated(
        DataTypes.StrategyType indexed strategyType,
        uint256 amount
    );
    event FundsWithdrawn(
        DataTypes.StrategyType indexed strategyType,
        uint256 amount
    );
    event PoolAdded(string indexed poolName, address poolAddress);
    event PoolDeposit(
        string indexed poolName,
        address indexed asset,
        uint256 amount
    );
    event PoolWithdraw(
        string indexed poolName,
        address indexed asset,
        uint256 amount
    );

    /**
     * @dev Constructor initializes the vault with initial configurations
     * @param _admin Address of the admin
     * @param _asset Address of the underlying asset
     * @param _name Name of the vault token
     * @param _symbol Symbol of the vault token
     * @param _agentAddress Address of the agent
     * @param _aavePool Address of the Aave pool
     * @param _balancerVault Address of the Balancer vault
     */
    constructor(
        address _admin,
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        address _agentAddress,
        address _aavePool,
        address _balancerVault
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        vaultInfo.admin = _admin;
        vaultInfo.asset = address(_asset);
        vaultInfo.agent = _agentAddress;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(AGENT_ROLE, _agentAddress);

        // Deploy strategies
        IAaveV3Pool aaveStrategy = IAaveV3Pool(_aavePool);
        strategies[DataTypes.StrategyType.AAVE] = address(aaveStrategy);
        emit StrategyDeployed(
            DataTypes.StrategyType.AAVE,
            address(aaveStrategy)
        );

        BalancerStrategy balancerStrategy = new BalancerStrategy(
            _balancerVault,
            address(this)
        );
        strategies[DataTypes.StrategyType.BALANCER] = address(balancerStrategy);
        emit StrategyDeployed(
            DataTypes.StrategyType.BALANCER,
            address(balancerStrategy)
        );

        // Añadir Aave como primer pool
        _addPool("AAVE", _aavePool);
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "SuperVault: admin only");
        _;
    }

    modifier onlyAgent() {
        require(hasRole(AGENT_ROLE, msg.sender), "SuperVault: agent only");
        _;
    }

    /**
     * @dev Allocates funds to a specific strategy
     * @param strategyType Type of strategy to allocate funds to
     * @param amount Amount of funds to allocate
     */
    function allocateToStrategy(
        DataTypes.StrategyType strategyType,
        uint256 amount
    ) external onlyAgent nonReentrant {
        require(amount > 0, "SuperVault: zero amount");
        require(
            strategies[strategyType] != address(0),
            "SuperVault: strategy not found"
        );
        require(
            amount <= IERC20(vaultInfo.asset).balanceOf(address(this)),
            "SuperVault: insufficient balance"
        );

        IERC20(vaultInfo.asset).approve(strategies[strategyType], amount);
        ILending(strategies[strategyType]).deposit(vaultInfo.asset, amount);
        vaultInfo.totalAllocatedFunds += amount;

        emit FundsAllocated(strategyType, amount);
    }

    function withdrawFromStrategy(
        DataTypes.StrategyType strategyType,
        uint256 amount
    ) external onlyAgent nonReentrant {
        require(amount > 0, "SuperVault: zero amount");
        require(
            strategies[strategyType] != address(0),
            "SuperVault: strategy not found"
        );

        ILending(strategies[strategyType]).withdraw(vaultInfo.asset, amount);
        vaultInfo.totalAllocatedFunds -= amount;

        emit FundsWithdrawn(strategyType, amount);
    }

    function addLiquidityToBalancer(
        bytes32 poolId,
        IAsset[] memory assets,
        uint256[] memory maxAmountsIn,
        bytes memory userData
    ) external onlyAgent nonReentrant {
        address balancerStrategy = strategies[DataTypes.StrategyType.BALANCER];
        require(
            balancerStrategy != address(0),
            "SuperVault: Balancer strategy not found"
        );

        // Transfer assets to Balancer strategy
        for (uint256 i = 0; i < assets.length; i++) {
            IERC20(address(assets[i])).approve(
                balancerStrategy,
                maxAmountsIn[i]
            );
        }

        BalancerStrategy(balancerStrategy).addLiquidity(
            poolId,
            assets,
            maxAmountsIn,
            userData
        );
    }

    function removeLiquidityFromBalancer(
        bytes32 poolId,
        IAsset[] memory assets,
        uint256[] memory minAmountsOut,
        bytes memory userData
    ) external onlyAgent nonReentrant {
        address balancerStrategy = strategies[DataTypes.StrategyType.BALANCER];
        require(
            balancerStrategy != address(0),
            "SuperVault: Balancer strategy not found"
        );

        BalancerStrategy(balancerStrategy).removeLiquidity(
            poolId,
            assets,
            minAmountsOut,
            userData
        );
    }

    function deposit(uint256 amount) external nonReentrant {
        _deposit(msg.sender, msg.sender, amount, amount);
    }

    function withdraw(uint256 shares) external nonReentrant {
        _withdraw(msg.sender, msg.sender, msg.sender, shares, shares);
    }

    /**
     * @dev Returns the total assets managed by the vault
     * @return Total assets including vault balance and allocated funds
     */
    function totalAssets() public view virtual override returns (uint256) {
        uint256 vaultBalance = IERC20(asset()).balanceOf(address(this));
        uint256 strategiesBalance = vaultInfo.totalAllocatedFunds;
        return vaultBalance + strategiesBalance;
    }

    function getStrategyAddress(
        DataTypes.StrategyType strategyType
    ) external view returns (address) {
        return strategies[strategyType];
    }

    function addPool(
        string calldata poolName,
        address poolAddress
    ) external onlyAdmin {
        _addPool(poolName, poolAddress);
    }

    function _addPool(string memory poolName, address poolAddress) internal {
        require(poolAddress != address(0), "SuperVault: zero pool address");
        require(
            !lendingPools[poolName].isActive,
            "SuperVault: pool already exists"
        );
        require(bytes(poolName).length > 0, "SuperVault: empty pool name");

        lendingPools[poolName].poolAddress = poolAddress;
        lendingPools[poolName].isActive = true;
        poolList.push(poolName);

        emit PoolAdded(poolName, poolAddress);
    }

    function depositToPool(
        string calldata poolName,
        uint256 amount
    ) external onlyAgent nonReentrant {
        require(amount > 0, "SuperVault: zero amount");
        require(lendingPools[poolName].isActive, "SuperVault: pool not found");
        require(
            amount <= IERC20(vaultInfo.asset).balanceOf(address(this)),
            "SuperVault: insufficient balance"
        );

        LendingPool storage pool = lendingPools[poolName];
        address poolAddress = pool.poolAddress;

        IERC20 token = IERC20(vaultInfo.asset);
        if (token.allowance(address(this), poolAddress) < amount) {
            token.forceApprove(poolAddress, amount);
        }

        IAaveV3Pool(poolAddress).supply(
            vaultInfo.asset,
            amount,
            address(this),
            0
        );
        pool.deposits[vaultInfo.asset] += amount;
        vaultInfo.totalAllocatedFunds += amount;

        emit PoolDeposit(poolName, vaultInfo.asset, amount);
    }

    function withdrawFromPool(
        string calldata poolName,
        uint256 amount
    ) external onlyAgent nonReentrant {
        require(amount > 0, "SuperVault: zero amount");
        require(lendingPools[poolName].isActive, "SuperVault: pool not found");

        LendingPool storage pool = lendingPools[poolName];
        require(
            amount <= pool.deposits[vaultInfo.asset],
            "SuperVault: insufficient pool balance"
        );

        DataTypes.ReserveData memory reserveData = IAaveV3Pool(pool.poolAddress)
            .getReserveData(vaultInfo.asset);
        require(
            reserveData.aTokenAddress != address(0),
            "SuperVault: aToken not found"
        );

        IERC20 aToken = IERC20(reserveData.aTokenAddress);
        if (aToken.allowance(address(this), pool.poolAddress) < amount) {
            aToken.forceApprove(pool.poolAddress, 0);
            aToken.forceApprove(pool.poolAddress, amount);
        }

        IAaveV3Pool(pool.poolAddress).withdraw(
            vaultInfo.asset,
            amount,
            address(this)
        );
        pool.deposits[vaultInfo.asset] -= amount;
        vaultInfo.totalAllocatedFunds -= amount;

        emit PoolWithdraw(poolName, vaultInfo.asset, amount);
    }

    /**
     * @dev Utility function to get pool balance for a specific asset
     * @param poolName Name of the pool
     * @param asset Address of the asset
     * @return Balance of the asset in the specified pool
     */
    function getPoolBalance(
        string calldata poolName,
        address asset
    ) external view returns (uint256) {
        require(lendingPools[poolName].isActive, "SuperVault: pool not found");
        return lendingPools[poolName].deposits[asset];
    }

    function getPoolAddress(
        string calldata poolName
    ) external view returns (address) {
        require(lendingPools[poolName].isActive, "SuperVault: pool not found");
        return lendingPools[poolName].poolAddress;
    }

    function getPoolList() external view returns (string[] memory) {
        return poolList;
    }

    function setAgent(address _agent) external onlyAdmin {
        vaultInfo.agent = _agent;
        _grantRole(AGENT_ROLE, _agent);
    }

    function setAdmin(address _admin) external onlyAdmin {
        vaultInfo.admin = _admin;
        _grantRole(ADMIN_ROLE, _admin);
    }
}
