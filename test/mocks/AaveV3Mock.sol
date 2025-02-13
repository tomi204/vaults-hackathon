// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../src/interfaces/IAaveV3Pool.sol";
import "../../src/libraries/DataTypes.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockAToken is ERC20 {
    using SafeERC20 for IERC20;

    address public immutable underlyingAsset;
    address public immutable pool;

    constructor(
        string memory name,
        string memory symbol,
        address _underlyingAsset,
        address _pool
    ) ERC20(name, symbol) {
        underlyingAsset = _underlyingAsset;
        pool = _pool;
    }

    function mint(address account, uint256 amount) external {
        require(msg.sender == pool, "Only pool can mint");
        _mint(account, amount);
    }

    function burn(address account, uint256 amount) external {
        require(msg.sender == pool, "Only pool can burn");
        _burn(account, amount);
    }
}

contract AaveV3Mock is IAaveV3Pool {
    using SafeERC20 for IERC20;

    mapping(address => DataTypes.ReserveData) private _reserves;
    mapping(address => MockAToken) public aTokens;
    mapping(address => mapping(address => uint256)) private _userBalances;

    function supply(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16
    ) external override {
        require(amount > 0, "Amount must be greater than 0");

        // Create aToken if it doesn't exist
        if (address(aTokens[asset]) == address(0)) {
            string memory symbol = ERC20(asset).symbol();
            MockAToken aToken = new MockAToken(
                string(abi.encodePacked("Aave ", symbol)),
                string(abi.encodePacked("a", symbol)),
                asset,
                address(this)
            );
            aTokens[asset] = aToken;
            _reserves[asset].aTokenAddress = address(aToken);
        }

        // Transfer asset to this contract
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        // Mint aTokens to receiver and update balance
        aTokens[asset].mint(onBehalfOf, amount);
        _userBalances[asset][onBehalfOf] += amount;
    }

    function withdraw(
        address asset,
        uint256 amount,
        address to
    ) external returns (uint256) {
        MockAToken aToken = aTokens[asset];
        require(address(aToken) != address(0), "Asset not supported");
        require(
            _userBalances[asset][msg.sender] >= amount,
            "Insufficient balance"
        );

        // Burn aTokens and update balance
        aToken.burn(msg.sender, amount);
        _userBalances[asset][msg.sender] -= amount;

        // Transfer underlying asset
        IERC20(asset).safeTransfer(to, amount);

        return amount;
    }

    function getReserveData(
        address asset
    ) external view override returns (DataTypes.ReserveData memory) {
        return _reserves[asset];
    }

    function getUserBalance(
        address asset,
        address user
    ) external view returns (uint256) {
        return _userBalances[asset][user];
    }
}
