// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IRoyaltyManager {
    function calculateRoyaltyFee(address pair, uint256[] memory tokenIds, uint256 price)
        external
        view
        returns (address, uint256);
}
