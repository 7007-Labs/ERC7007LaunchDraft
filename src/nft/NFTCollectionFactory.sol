// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {INFTCollectionFactory} from "../interfaces/INFTCollectionFactory.sol";
// import {ORAERC7007Impl} from "./ORAERC7007Impl.sol";

contract NFTCollectionFactory is INFTCollectionFactory, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    address public implementationNFTCollection;

    mapping(address => bool) public providerAllowed;
    mapping(uint256 => bool) public oraModelAllowed;

    function initialize(address owner, address _implementation) external initializer {
        __Ownable_init(owner);
        implementationNFTCollection = _implementation;
    }

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
    ) external returns (address collection) {
        // 暂时只支持ORA的ai provider，后续有不能兼容的，需要更新合约来支持
        require(providerAllowed[provider]);
        uint256 modelId = abi.decode(providerParams, (uint256));
        require(oraModelAllowed[modelId]);
        ERC1967Proxy proxy = new ERC1967Proxy(implementationNFTCollection, "");
        // ORAERC7007Impl(address(proxy)).initialize(
        //     name, symbol, prompt, initialOwner, totalSupply, msg.sender, nsfw, modelId
        // );
        return address(proxy);
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
