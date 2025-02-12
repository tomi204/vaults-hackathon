// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface ILending {
    function deposit(address asset, uint256 amount) external;

    function withdraw(address asset, uint256 amount) external;

    function getBalance(address asset) external view returns (uint256);
}
