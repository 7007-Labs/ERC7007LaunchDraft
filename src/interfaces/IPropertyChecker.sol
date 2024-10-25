// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IPropertyChecker {
    function hasProperties(uint256[] calldata ids, bytes calldata params) external returns (bool);
}
