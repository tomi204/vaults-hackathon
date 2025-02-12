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
import "./strategies/AaveStrategy.sol";
import "./strategies/BalancerStrategy.sol";

contract SuperVault is ERC4626, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");

    DataTypes.VaultInfo private vaultInfo;
    mapping(DataTypes.StrategyType => address) public strategies;

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
        AaveStrategy aaveStrategy = new AaveStrategy(_aavePool, address(this));
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
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "SuperVault: admin only");
        _;
    }

    modifier onlyAgent() {
        require(hasRole(AGENT_ROLE, msg.sender), "SuperVault: agent only");
        _;
    }

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
        _withdraw(msg.sender, msg.sender, msg.sender, shares, 0);
    }

    function withdrawAll() external nonReentrant {
        _withdraw(msg.sender, msg.sender, msg.sender, balanceOf(msg.sender), 0);
    }

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
}
