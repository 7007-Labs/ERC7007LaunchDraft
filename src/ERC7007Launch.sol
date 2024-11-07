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
    uint256 public constant maxNFTTotalSupply = 7007;
    address public immutable token7007;
    address public immutable nftCollectionFactory;
    address public immutable pairFactory;

    bool public isEnableWaitlist;

    constructor(address _nftCollectionFactory, address _pairFactory, address _token7007) {
        nftCollectionFactory = _nftCollectionFactory;
        pairFactory = _pairFactory;
        token7007 = _token7007;
        _disableInitializers();
    }

    function initialize(
        address owner
    ) external initializer {
        __Ownable_init(owner);
        __Pausable_init();
        isEnableWaitlist = true;
    }

    function _checkWaitlist(
        bytes32[] calldata proof
    ) internal view {
        if (isEnableWaitlist) {
            require(verifyWhitelistAddress(msg.sender, proof), "Address not whitelisted");
        }
    }

    struct LaunchParams {
        string name;
        string symbol;
        string basePrompt;
        bool nsfw;
        address provider;
        bytes providerParams;
        address bondingCurve;
        uint256 totalSupply;
        uint256 initialBuyNum;
        uint256 initialPrice;
        uint64 preSaleStart;
        uint64 preSaleEnd;
        bytes32[] whitelistProof;
    }

    function launch(
        LaunchParams calldata params
    ) external payable whenNotPaused {
        // check initialBuyNum
        require(params.initialBuyNum > 0);
        require(params.totalSupply <= maxNFTTotalSupply);
        _checkWaitlist(params.whitelistProof);
        address collection = INFTCollectionFactory(nftCollectionFactory).createNFTCollection(
            params.name,
            params.symbol,
            params.basePrompt,
            msg.sender,
            params.nsfw,
            params.provider,
            params.providerParams
        );

        bytes memory data = abi.encodePacked(params.totalSupply);
        address pair = IPairFactory(pairFactory).createPairERC7007ETH(
            msg.sender, collection, params.bondingCurve, PairType.LAUNCH, address(0), data
        );

        IORAERC7007(collection).activate(params.totalSupply, pair, pair);

        // burn token7007
        // uint256 burnTokenAmount = 0; // todo: 计算要burn的数目，需要操作时，用户需要授权给当前合约
        // IERC20(token7007).transferFrom(msg.sender, address(0), burnTokenAmount);

        IPair(pair).swapTokenForNFTs(1, msg.value, msg.sender, true, msg.sender);
    }

    function swapTokenForNFTs(
        address pair,
        uint256 nftNum,
        uint256 maxExpectedTokenInput,
        address nftRecipient,
        bytes32[] calldata whitelistProof
    ) external payable whenNotPaused returns (uint256, uint256) {
        _checkWaitlist(whitelistProof);
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
        _checkWaitlist(whitelistProof);
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
        _checkWaitlist(whitelistProof);
        return IPair(pair).swapNFTsForToken(tokenIds, minExpectedTokenOutput, tokenRecipient, true, msg.sender);
    }

    function setWhitelistMerkleRoot(
        bytes32 root
    ) external onlyOwner {
        _setWhitelistMerkleRoot(root);
    }

    function disableWaitlist() public onlyOwner {
        isEnableWaitlist = false;
    }

    function enableWaitlist() public onlyOwner {
        isEnableWaitlist = true;
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
