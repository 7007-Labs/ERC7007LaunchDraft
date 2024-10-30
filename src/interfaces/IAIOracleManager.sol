// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IAIOracleManager {
    function estimateFee(address nft, uint256 size) external view returns (uint256);

    function reveal(address nft, uint256[] memory tokenIds) external payable;

    function isTokenFinalized(address nft, uint256 tokenId) external view returns (bool);
}
