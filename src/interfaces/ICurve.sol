// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface ICurve {
    function getBuyPrice(address pair, uint256 numItems) external view returns (uint256 inputValue);

    function getSellPrice(address pair, uint256 numItems) external view returns (uint256 outputValue);
}
