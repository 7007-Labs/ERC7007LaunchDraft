// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IRoyaltyManager {
    function calculateRoyaltyFeeAndGetRecipient(address collection, uint256 tokenId, uint256 amount)
        external
        view
        returns (address, uint256);
}
