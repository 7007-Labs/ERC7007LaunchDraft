// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {INFTCollectionFactory} from "../interfaces/INFTCollectionFactory.sol";
import {ORAERC7007Impl} from "./ORAERC7007Impl.sol";

contract NFTCollectionFactory is INFTCollectionFactory, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    address public nftCollectionImpl;

    mapping(address => bool) public providerAllowed;
    mapping(uint256 => bool) public oraModelAllowed;

    function initialize(address owner, address _implementation) external initializer {
        __Ownable_init(owner);
        nftCollectionImpl = _implementation;
    }

    function createNFTCollection(
        string calldata name,
        string calldata symbol,
        string calldata prompt,
        address _owner,
        bool nsfw,
        address provider,
        bytes calldata providerParams
    ) external returns (address collection) {
        require(providerAllowed[provider]);
        uint256 modelId = abi.decode(providerParams, (uint256));
        require(oraModelAllowed[modelId]);

        collection = _deployNFTCollection(provider, modelId, prompt);
        ORAERC7007Impl(collection).initialize(name, symbol, prompt, _owner, nsfw, modelId);
    }

    function _deployNFTCollection(
        address provider,
        uint256 modelId,
        string calldata prompt
    ) internal returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(provider, modelId, prompt));
        bytes memory initCode = abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(nftCollectionImpl));
        return Create2.deploy(0, salt, initCode);
    }

    function _authorizeUpgrade(
        address
    ) internal override onlyOwner {}

    function setProviderAllowed(address provider, bool isAllowed) external onlyOwner {
        providerAllowed[provider] = isAllowed;
    }

    function setORAModelAllowed(uint256 modelId, bool isAllowed) external onlyOwner {
        oraModelAllowed[modelId] = isAllowed;
    }
}
