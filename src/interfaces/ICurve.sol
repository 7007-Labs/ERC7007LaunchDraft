// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface ICurve {
    function getBuyPrice(uint256 totalSupply, uint256 numItems) external view returns (uint256 inputValue);

    function getSellPrice(uint256 totalSupply, uint256 numItems) external view returns (uint256 outputValue);
}
