// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

contract SuperVault is ERC4626, AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");

    IERC20 public immutable token;

    constructor(
        address _token,
        address _admin,
        IERC20 _asset,
        string memory _name,
        string memory _symbol,
        address _agentAddress
    ) ERC4626(_asset) ERC20(_name, _symbol) {
        token = IERC20(_token);
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(AGENT_ROLE, _agentAddress);
    }

    /// @notice Restricts function access to admin role holders
    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "SuperVault: admin only");
        _;
    }

    /// @notice Restricts function access to agent role holders
    modifier onlyAgent() {
        require(hasRole(AGENT_ROLE, msg.sender), "SuperVault: agent only");
        _;
    }
}
