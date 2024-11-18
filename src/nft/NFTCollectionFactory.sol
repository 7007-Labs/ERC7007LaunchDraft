// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {INFTCollectionFactory} from "../interfaces/INFTCollectionFactory.sol";
import {ORAERC7007Impl} from "./ORAERC7007Impl.sol";

contract NFTCollectionFactory is INFTCollectionFactory, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    address public nftCollectionImpl;

    mapping(address => bool) public allowlist;
    mapping(address => bool) public providerAllowed;
    mapping(uint256 => bool) public oraModelAllowed;

    error UnauthorizedCaller();
    error ProviderNotAllowed();
    error ORAModelNotAllowed();

    event ProviderStatusUpdate(address indexed provider, bool isAllowed);
    event ORAModelStatusUpdate(uint256 indexed modelId, bool isAllowed);
    event AllowlistStatusUpdate(address indexed addr, bool isAllowed);

    function initialize(address owner, address _implementation) external initializer {
        __Ownable_init(owner);
        nftCollectionImpl = _implementation;
    }

    modifier onlyAllowlist() {
        if (!allowlist[msg.sender]) revert UnauthorizedCaller();
        _;
    }

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
        ORAERC7007Impl(collection).initialize(metadataInitializer, _owner, modelId);
    }

    function _deployNFTCollection(
        address provider,
        uint256 modelId,
        string calldata prompt
    ) internal returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(provider, modelId, prompt));
        return Clones.cloneDeterministic(nftCollectionImpl, salt);
    }

    function _authorizeUpgrade(
        address
    ) internal override onlyOwner {}

    function setProviderAllowed(address provider, bool isAllowed) external onlyOwner {
        providerAllowed[provider] = isAllowed;
        emit ProviderStatusUpdate(provider, isAllowed);
    }

    function setORAModelAllowed(uint256 modelId, bool isAllowed) external onlyOwner {
        oraModelAllowed[modelId] = isAllowed;
        emit ORAModelStatusUpdate(modelId, isAllowed);
    }

    function setAllowlistAllowed(address addr, bool isAllowed) external onlyOwner {
        allowlist[addr] = isAllowed;
        emit AllowlistStatusUpdate(addr, isAllowed);
    }
}
