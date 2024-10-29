// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface INFTCollectionFactory {
    function createNFTCollection(
        string calldata name,
        string calldata symbol,
        string calldata prompt,
        address initialOwner,
        uint256 totalSupply,
        // address defaultMintTo,
        bool nsfw,
        address provider,
        bytes calldata providerParams
    ) external returns (address collection);
}
