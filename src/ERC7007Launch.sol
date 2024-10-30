// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {PairType} from "./enums/PairType.sol";
import {INFTCollectionFactory} from "./interfaces/INFTCollectionFactory.sol";
import {IPairFactory} from "./interfaces/IPairFactory.sol";
import {ICurve} from "./interfaces/ICurve.sol";
import {IPair} from "./interfaces/IPair.sol";

contract ERC7007Launch is Initializable, OwnableUpgradeable, UUPSUpgradeable, PausableUpgradeable {
    address public immutable nftCollectionFactory;
    address public immutable pairFactory;
    bool activeWaitlist;
    uint256 public defaultNFTTotalSupply = 7007;

    constructor(address _nftCollectionFactory, address _pairFactory) {
        nftCollectionFactory = _nftCollectionFactory;
        pairFactory = _pairFactory;
        _disableInitializers();
    }

    function initialize(
        address owner
    ) external initializer {
        __Ownable_init(owner);
        __Pausable_init();
        activeWaitlist = true;
    }

    function _authorizeUpgrade(
        address
    ) internal override onlyOwner {}

    function launch(
        string calldata name,
        string calldata symbol,
        string calldata basePrompt,
        bool nsfw,
        ICurve bondingCurve,
        uint256 providerId,
        bytes calldata providerParams
    ) external payable {
        // 1.调用NFTCollectionFactory创建NFTCollection
        // address collection =
        //     INFTCollectionFactory(nftCollectionFactory).createNFTCollection(
        //         name, symbol, basePrompt, msg.sender,
        //         defaultNFTTotalSupply,
        //     );
        // 2.调用PairFactory创建pair

        // address pair = IPairFactory(pairFactory).createPairERC7007ETH(
        //     collection, bondingCurve, PairType, address(0), address(0), ""
        // );
        // 3. mintAll to pair

        // IPair(pair).
    }

    // router
    function swapTokenForNFTs(
        address pairAddress,
        uint256 nftNum,
        uint256[] calldata desiredTokenIds,
        uint256 maxExpectedTokenInput,
        address nftRecipient
    ) external payable {}

    function swapNFTsForToken(
        uint256[] calldata nftIds,
        uint256 minExpectedTokenOutput,
        address payable tokenRecipient
    ) external returns (uint256) {
        // if (nftIds.length == 0) revert ZeroSwapAmount();
        // uint256 price = ICurve(bondingCurve).getBuyPrice(address(this), nftIds.length);
        return 0;
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
}
