// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface INFTCollectionFactory {
    function createNFTCollection(string memory name, string memory symbol, string memory basePrompt, address owner)
        external
        returns (address collection);
}
