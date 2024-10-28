// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {INFTCollectionFactory} from "./interfaces/INFTCollectionFactory.sol";

contract ERC7007Launch is Initializable, OwnableUpgradeable, UUPSUpgradeable, PausableUpgradeable {
    address public immutable nftCollectionFactory;
    address public immutable pairFactory;
    bool activeWaitlist;

    constructor(address _nftCollectionFactory, address _pairFactory) {
        nftCollectionFactory = _nftCollectionFactory;
        pairFactory = _pairFactory;
        _disableInitializers();
    }

    function initialize(address owner) external initializer {
        __Ownable_init(owner);
        __Pausable_init();
        activeWaitlist = true;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function launch(
        string memory name,
        string memory symbol,
        string memory basePrompt,
        bool nsfw,
        uint256 providerId,
        bytes calldata modelParams
    ) external payable {
        // 1.调用NFTCollectionFactory创建NFTCollection
        address collection =
            INFTCollectionFactory(nftCollectionFactory).createNFTCollection(name, symbol, basePrompt, msg.sender);
        // 2.调用PairFactory创建pair

        // 3.通过pair购买一个nft
    }

    // trader
    function swapTokenForNFTs(
        address pairAddress,
        uint256 nftNum,
        uint256[] calldata desiredTokenIds,
        uint256 maxExpectedTokenInput,
        address nftRecipient
    ) external payable {}

    function swapNFTsForToken(uint256[] calldata nftIds, uint256 minExpectedTokenOutput, address payable tokenRecipient)
        external
        nonReentrant
        returns (uint256)
    {
        if (nftIds.length == 0) revert ZeroSwapAmount();
        uint256 price = ICurve(bondingCurve).getBuyPrice(address(this), nftIds.length);
    }

    function stopWaitlist() public onlyOwner {
        activeWaitlist = false;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    // todo: add router
    // 1. whitelist
    // 2. pause

    // router
    // 1. event
    // 2. a-b-c
    // 3. sell nft, nft -> router

    // v4
    // pair(pool)
    //
    // pool => asset address => balance
    // nft -> ft
    // 4. nft vault, 1.pause 2. inner transfer (a -> b-> c => a -c) 3.approvel
}

// factory -> pool  only Factory()
// owner(creator) -> pair
// eigenlayer pool, all pool -> manager address
