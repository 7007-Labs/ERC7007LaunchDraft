// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface INFTCollectionFactory {
    function createNFTCollection(
        address _owner,
        string calldata prompt,
        bytes calldata metadtaInitializer,
        address provider,
        bytes calldata providerParams
    ) external returns (address collection);
}
