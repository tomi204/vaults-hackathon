// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/ILending.sol";
import "../interfaces/IAaveV3Pool.sol";

contract AaveStrategy is ILending, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    IAaveV3Pool public immutable aavePool;
    mapping(address => uint256) public aaveDeposits;
    address public vault;

    event Deposited(address indexed asset, uint256 amount);
    event Withdrawn(address indexed asset, uint256 amount);

    constructor(address _aavePool, address _vault) {
        require(_aavePool != address(0), "AaveStrategy: zero pool address");
        require(_vault != address(0), "AaveStrategy: zero vault address");
        aavePool = IAaveV3Pool(_aavePool);
        vault = _vault;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VAULT_ROLE, _vault);
    }

    modifier onlyVault() {
        require(hasRole(VAULT_ROLE, msg.sender), "AaveStrategy: only vault");
        _;
    }

    function deposit(
        address asset,
        uint256 amount
    ) external override onlyVault {
        require(amount > 0, "AaveStrategy: zero amount");

        // Transfer asset from vault to this contract
        IERC20(asset).safeTransferFrom(vault, address(this), amount);

        // Approve Aave pool to spend the asset if needed
        IERC20 token = IERC20(asset);
        if (token.allowance(address(this), address(aavePool)) < amount) {
            token.forceApprove(address(aavePool), amount);
        }

        // Supply to Aave
        aavePool.supply(asset, amount, address(this), 0);
        aaveDeposits[asset] += amount;

        emit Deposited(asset, amount);
    }

    function withdraw(
        address asset,
        uint256 amount
    ) external override onlyVault {
        require(amount > 0, "AaveStrategy: zero amount");
        require(
            amount <= aaveDeposits[asset],
            "AaveStrategy: insufficient balance"
        );

        // Get aToken for this asset
        DataTypes.ReserveData memory reserveData = aavePool.getReserveData(
            asset
        );
        require(
            reserveData.aTokenAddress != address(0),
            "AaveStrategy: aToken not found"
        );

        // Approve aToken spending if needed
        IERC20 aToken = IERC20(reserveData.aTokenAddress);
        if (aToken.allowance(address(this), address(aavePool)) < amount) {
            aToken.forceApprove(address(aavePool), 0);
            aToken.forceApprove(address(aavePool), amount);
        }

        // Withdraw from Aave
        aavePool.withdraw(asset, amount, payable(vault));
        aaveDeposits[asset] -= amount;

        emit Withdrawn(asset, amount);
    }

    function getBalance(
        address asset
    ) external view override returns (uint256) {
        return aaveDeposits[asset];
    }
}
