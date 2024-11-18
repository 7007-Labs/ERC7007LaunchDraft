// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PairType} from "./enums/PairType.sol";
import {INFTCollectionFactory} from "./interfaces/INFTCollectionFactory.sol";
import {IPairFactory} from "./interfaces/IPairFactory.sol";
import {ICurve} from "./interfaces/ICurve.sol";
import {IPair} from "./interfaces/IPair.sol";
import {IORAERC7007} from "./interfaces/IORAERC7007.sol";
import {Whitelist} from "./libraries/Whitelist.sol";

contract ERC7007Launch is Whitelist, Initializable, OwnableUpgradeable, UUPSUpgradeable, PausableUpgradeable {
    uint64 public constant NFT_TOTAL_SUPPLY = 7007;
    uint64 public constant MAX_INIT_BUY_NUM = 10;
    address public immutable nftCollectionFactory;
    address public immutable pairFactory;

    bool public isEnableWhitelist;

    error InvalidInitialBuyNum();

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
        isEnableWhitelist = true;
    }

    function _checkWhitelist(
        bytes32[] calldata proof
    ) internal view {
        if (isEnableWhitelist) {
            require(verifyWhitelistAddress(msg.sender, proof), "Address not whitelisted");
        }
    }

    struct LaunchParams {
        bytes metadataInitializer;
        string prompt;
        address provider;
        bytes providerParams;
        address bondingCurve;
        uint256 initialBuyNum;
        uint96 initialPrice;
        uint64 preSaleStart;
        uint64 preSaleEnd;
        bytes32 presaleMerkleRoot;
        bytes32[] whitelistProof;
    }

    function launch(
        LaunchParams calldata params
    ) external payable whenNotPaused {
        if (params.initialBuyNum == 0 || params.initialBuyNum > MAX_INIT_BUY_NUM) revert InvalidInitialBuyNum();
        _checkWhitelist(params.whitelistProof);

        address collection = INFTCollectionFactory(nftCollectionFactory).createNFTCollection(
            msg.sender, params.prompt, params.metadataInitializer, params.provider, params.providerParams
        );

        bytes memory data = abi.encodePacked(NFT_TOTAL_SUPPLY);
        address pair =
            IPairFactory(pairFactory).createPairERC7007ETH(msg.sender, collection, PairType.LAUNCH, address(0), data);

        IORAERC7007(collection).activate(NFT_TOTAL_SUPPLY, pair, pair);

        IPair(pair).swapTokenForNFTs(params.initialBuyNum, msg.value, msg.sender, true, msg.sender);
    }

    function purchasePresaleNFTs(
        address pair,
        uint256 nftNum,
        uint256 maxExpectedTokenInput,
        address nftRecipient,
        bytes32[] calldata whitelistProof,
        bytes32[] calldata presaleMerkleProof
    ) external payable whenNotPaused returns (uint256, uint256) {
        _checkWhitelist(whitelistProof);
        return IPair(pair).purchasePresale(
            nftNum, maxExpectedTokenInput, nftRecipient, presaleMerkleProof, true, msg.sender
        );
    }

    function swapTokenForNFTs(
        address pair,
        uint256 nftNum,
        uint256 maxExpectedTokenInput,
        address nftRecipient,
        bytes32[] calldata whitelistProof
    ) external payable whenNotPaused returns (uint256, uint256) {
        _checkWhitelist(whitelistProof);
        return IPair(pair).swapTokenForNFTs(nftNum, maxExpectedTokenInput, nftRecipient, true, msg.sender);
    }

    function swapTokenForSpecificNFTs(
        address pair,
        uint256[] calldata tokenIds,
        uint256 maxNFTNum,
        uint256 minNFTNum,
        uint256 maxExpectedTokenInput,
        address nftRecipient,
        bytes32[] calldata whitelistProof
    ) external payable returns (uint256, uint256) {
        _checkWhitelist(whitelistProof);
        return IPair(pair).swapTokenForSpecificNFTs(
            tokenIds, maxNFTNum, minNFTNum, maxExpectedTokenInput, nftRecipient, true, msg.sender
        );
    }

    function swapNFTsForToken(
        address pair,
        uint256[] calldata tokenIds,
        uint256 minExpectedTokenOutput,
        address payable tokenRecipient,
        bytes32[] calldata whitelistProof
    ) external whenNotPaused returns (uint256) {
        _checkWhitelist(whitelistProof);
        return IPair(pair).swapNFTsForToken(tokenIds, minExpectedTokenOutput, tokenRecipient, true, msg.sender);
    }

    function setWhitelistMerkleRoot(
        bytes32 root
    ) external onlyOwner {
        _setWhitelistMerkleRoot(root);
    }

    function disableWhitelist() public onlyOwner {
        isEnableWhitelist = false;
    }

    function enableWhitelist() public onlyOwner {
        isEnableWhitelist = true;
    }

    function _authorizeUpgrade(
        address
    ) internal override onlyOwner {}

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
}
