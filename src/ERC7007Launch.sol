// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {INFTCollectionFactory} from "./interfaces/INFTCollectionFactory.sol";

contract ERC7007Launch is Initializable, OwnableUpgradeable, UUPSUpgradeable {
    address public immutable nftCollectionFactory;
    address public immutable pairFactory;

    constructor(address _nftCollectionFactory, address _pairFactory) {
        nftCollectionFactory = _nftCollectionFactory;
        pairFactory = _pairFactory;
        _disableInitializers();
    }

    function initialize(address owner) external initializer {
        __Ownable_init(owner);
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    // 调用方: 用户
    // 调用方权限要求: 只能Launch调用
    // todo: 完善
    function launch(string memory name, string memory symbol, string memory basePrompt, bool nsfw) external payable {
        // 1.调用NFTCollectionFactory创建NFTCollection
        address collection =
            INFTCollectionFactory(nftCollectionFactory).createNFTCollection(name, symbol, basePrompt, msg.sender);
        // 2.调用PairFactory创建pair

        // 3.通过pair购买一个nft
    }
}
