// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../interfaces/ILending.sol";
import "../interfaces/IBalancerV2.sol";

contract BalancerStrategy is ILending, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant VAULT_ROLE = keccak256("VAULT_ROLE");
    IBalancerV2 public immutable balancerVault;
    mapping(address => uint256) public balancerDeposits;
    address public vault;

    event Deposited(address indexed asset, uint256 amount);
    event Withdrawn(address indexed asset, uint256 amount);
    event LiquidityAdded(bytes32 indexed poolId, uint256[] amounts);
    event LiquidityRemoved(bytes32 indexed poolId, uint256[] amounts);

    constructor(address _balancerVault, address _vault) {
        require(
            _balancerVault != address(0),
            "BalancerStrategy: zero vault address"
        );
        require(_vault != address(0), "BalancerStrategy: zero vault address");
        balancerVault = IBalancerV2(_balancerVault);
        vault = _vault;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(VAULT_ROLE, _vault);
    }

    modifier onlyVault() {
        require(
            hasRole(VAULT_ROLE, msg.sender),
            "BalancerStrategy: only vault"
        );
        _;
    }

    function deposit(
        address asset,
        uint256 amount
    ) external override onlyVault {
        require(amount > 0, "BalancerStrategy: zero amount");

        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        balancerDeposits[asset] += amount;

        emit Deposited(asset, amount);
    }

    function withdraw(
        address asset,
        uint256 amount
    ) external override onlyVault {
        require(amount > 0, "BalancerStrategy: zero amount");
        require(
            amount <= balancerDeposits[asset],
            "BalancerStrategy: insufficient balance"
        );

        IERC20(asset).safeTransfer(msg.sender, amount);
        balancerDeposits[asset] -= amount;

        emit Withdrawn(asset, amount);
    }

    function getBalance(
        address asset
    ) external view override returns (uint256) {
        return balancerDeposits[asset];
    }

    function addLiquidity(
        bytes32 poolId,
        IAsset[] memory assets,
        uint256[] memory maxAmountsIn,
        bytes memory userData
    ) external onlyVault {
        IBalancerV2.JoinPoolRequest memory request = IBalancerV2
            .JoinPoolRequest({
                assets: assets,
                maxAmountsIn: maxAmountsIn,
                userData: userData,
                fromInternalBalance: false
            });

        // Approve tokens for Balancer vault
        for (uint256 i = 0; i < assets.length; i++) {
            IERC20(address(assets[i])).approve(
                address(balancerVault),
                maxAmountsIn[i]
            );
        }

        balancerVault.joinPool(poolId, address(this), payable(vault), request);

        emit LiquidityAdded(poolId, maxAmountsIn);
    }

    function removeLiquidity(
        bytes32 poolId,
        IAsset[] memory assets,
        uint256[] memory minAmountsOut,
        bytes memory userData
    ) external onlyVault {
        IBalancerV2.ExitPoolRequest memory request = IBalancerV2
            .ExitPoolRequest({
                assets: assets,
                minAmountsOut: minAmountsOut,
                userData: userData,
                toInternalBalance: false
            });

        balancerVault.exitPool(poolId, address(this), payable(vault), request);

        emit LiquidityRemoved(poolId, minAmountsOut);
    }
}
