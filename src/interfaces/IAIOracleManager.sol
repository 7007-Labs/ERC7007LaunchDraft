// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IAIOracleManager {
    function estimateFee(uint256 size) view returns (uint256);

    function unReveal(uint256[] memory tokenIds);
}
