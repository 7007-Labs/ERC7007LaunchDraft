// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {INFTCollectionFactory} from "../interfaces/INFTCollectionFactory.sol";

// todo: 考虑合并到Launch中
contract NFTCollectionFactory is INFTCollectionFactory, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    address public implementationNFTCollection;

    event NFTCollectionCreated(
        address indexed collection,
        address indexed creator,
        uint256 indexed version,
        string name,
        string symbol,
        uint256 nonce
    );

    constructor() {
        _disableInitializers();
    }

    function initialize(address owner, address _implementation) external initializer {
        __Ownable_init(owner);
        implementationNFTCollection = _implementation;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    // 调用方: Launch
    // 调用方权限要求: 只能Launch调用
    // todo: 完善
    function createNFTCollection(string memory name, string memory symbol, string memory basePrompt, address owner)
        external
        returns (address collection)
    {
        return address(0);
    }
}
