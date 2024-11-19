// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {INFTCollectionFactory} from "../interfaces/INFTCollectionFactory.sol";
import {ORAERC7007Impl} from "./ORAERC7007Impl.sol";

/**
 * @title NFT Collection Factory Contract
 * @notice Factory contract for deploying and managing NFT collections
 */
contract NFTCollectionFactory is INFTCollectionFactory, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    /// @dev Address of the implementation contract used as template for NFT collections
    address public nftCollectionImpl;

    /// @dev address => whether address is allowed to create NFT collections
    mapping(address => bool) public allowlist;

    /// @dev provider address => whether provider is approved
    mapping(address => bool) public providerAllowed;

    /// @dev ORA model ID => whether model is allowed
    mapping(uint256 => bool) public oraModelAllowed;

    error UnauthorizedCaller();
    error ProviderNotAllowed();
    error ORAModelNotAllowed();

    event ProviderStatusUpdate(address indexed provider, bool isAllowed);
    event ORAModelStatusUpdate(uint256 indexed modelId, bool isAllowed);
    event AllowlistStatusUpdate(address indexed addr, bool isAllowed);

    modifier onlyAllowlist() {
        if (!allowlist[msg.sender]) revert UnauthorizedCaller();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the factory contract
     * @param owner Address that will own the contract
     * @param _implementation Address of the NFT collection implementation contract
     */
    function initialize(address owner, address _implementation) external initializer {
        __Ownable_init(owner);
        nftCollectionImpl = _implementation;
    }

    /**
     * @notice Creates a new NFT collection with specified parameters
     * @param _owner Address that will own the new collection
     * @param prompt The initial prompt for the collection
     * @param metadataInitializer Initialization data for collection metadata
     * @param provider Address of the AI/ML model provider
     * @param providerParams Additional parameters for the provider (encoded)
     * @return collection Address of the newly created NFT collection
     */
    function createNFTCollection(
        address _owner,
        string calldata prompt,
        bytes calldata metadataInitializer,
        address provider,
        bytes calldata providerParams
    ) external onlyAllowlist returns (address collection) {
        if (!providerAllowed[provider]) revert ProviderNotAllowed();
        uint256 modelId = abi.decode(providerParams, (uint256));
        if (!oraModelAllowed[modelId]) revert ORAModelNotAllowed();

        collection = _deployNFTCollection(provider, modelId, prompt);
        ORAERC7007Impl(collection).initialize(_owner, prompt, metadataInitializer, modelId);
    }

    /**
     * @notice Internal function to deploy a new NFT collection using minimal proxy pattern
     * @param provider Address of the AI model provider
     * @param modelId ID of the model to be used
     * @param prompt The initial prompt for the collection
     * @return Address of the newly deployed collection
     */
    function _deployNFTCollection(
        address provider,
        uint256 modelId,
        string calldata prompt
    ) internal returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(provider, modelId, prompt));
        return Clones.cloneDeterministic(nftCollectionImpl, salt);
    }

    /**
     * @notice Update the approval status for a provider
     * @param provider Address of the provider to update
     * @param isAllowed New approval status
     */
    function setProviderAllowed(address provider, bool isAllowed) external onlyOwner {
        providerAllowed[provider] = isAllowed;
        emit ProviderStatusUpdate(provider, isAllowed);
    }

    /**
     * @notice Update the approval status for an ORA model
     * @param modelId ID of the ORA model to update
     * @param isAllowed New approval status
     */
    function setORAModelAllowed(uint256 modelId, bool isAllowed) external onlyOwner {
        oraModelAllowed[modelId] = isAllowed;
        emit ORAModelStatusUpdate(modelId, isAllowed);
    }

    /**
     * @notice Update the allowlist status for an address
     * @param addr Address to update
     * @param isAllowed New allowlist status
     */
    function setAllowlistAllowed(address addr, bool isAllowed) external onlyOwner {
        allowlist[addr] = isAllowed;
        emit AllowlistStatusUpdate(addr, isAllowed);
    }

    /**
     * @dev Required by UUPS pattern
     */
    function _authorizeUpgrade(
        address
    ) internal override onlyOwner {}
}
