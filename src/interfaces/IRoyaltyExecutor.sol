// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IRoyaltyExecutor {
    function calculateRoyalty(
        address pair,
        uint256 tokenId,
        uint256 price
    ) external view returns (address payable[] memory, uint256[] memory, uint256);
}
