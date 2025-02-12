// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

/**
 * @dev Interface for the SuperVault contract.
 */
interface ISuperVault {
    // Events
    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);
    event StrategyAdded(address indexed strategy);
    event StrategyRemoved(address indexed strategy);
    event AgentUpdated(address indexed newAgent);
    event AdminUpdated(address indexed newAdmin);
    event StrategyAllocation(address indexed strategy, uint256 amount);
    event StrategyWithdrawal(address indexed strategy, uint256 amount);
    event TokenRegistered(address indexed token);
    event TokenRemoved(address indexed token);
    event TokenSwapped(
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    // View functions
    function getBalance(address token) external view returns (uint256);

    function getStrategies() external view returns (address[] memory);

    function isStrategy(address strategy) external view returns (bool);

    function agent() external view returns (address);

    function admin() external view returns (bool);

    // Admin functions
    function setAgent(address newAgent) external;

    function setAdmin(address newAdmin) external;

    function addStrategy(address strategy) external;

    function removeStrategy(address strategy) external;

    function registerToken(address token) external;

    function removeToken(address token) external;

    // Agent functions
    function allocateToStrategy(address strategy, uint256 amount) external;

    function withdrawFromStrategy(address strategy, uint256 amount) external;

    // Roles
    function ADMIN_ROLE() external view returns (bytes32);

    function AGENT_ROLE() external view returns (bytes32);
}
