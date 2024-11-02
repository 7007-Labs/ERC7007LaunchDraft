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

contract ERC7007Launch is Initializable, OwnableUpgradeable, UUPSUpgradeable, PausableUpgradeable {
    uint256 public constant defaultNFTTotalSupply = 7007;
    address public immutable token7007;
    address public immutable nftCollectionFactory;
    address public immutable pairFactory;
    bool activeWaitlist;

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
        activeWaitlist = true;
    }

    function launch(
        string calldata name,
        string calldata symbol,
        string calldata basePrompt,
        bool nsfw,
        address provider,
        bytes calldata providerParams,
        ICurve bondingCurve,
        uint256 initialBuyNum
    ) external payable whenNotPaused {
        // check initialBuyNum
        require(initialBuyNum > 0);

        address collection = INFTCollectionFactory(nftCollectionFactory).createNFTCollection(
            name, symbol, basePrompt, msg.sender, nsfw, provider, providerParams
        );

        bytes memory data = abi.encodePacked(defaultNFTTotalSupply);
        address pair = IPairFactory(pairFactory).createPairERC7007ETH(
            collection, bondingCurve, PairType.LAUNCH, address(0), payable(address(0)), data
        );

        IORAERC7007(collection).activate(defaultNFTTotalSupply, pair, pair);

        // burn token7007
        uint256 burnTokenAmount = 0; // todo: 计算要burn的数目，需要操作时，用户需要授权给当前合约
        IERC20(token7007).transferFrom(msg.sender, address(0), burnTokenAmount);

        IPair(pair).swapTokenForNFTs(initialBuyNum, new uint256[](0), false, msg.value, msg.sender, true, msg.sender);
    }

    function swapTokenForNFTs(
        address pair,
        uint256 nftNum,
        uint256[] calldata desiredTokenIds,
        bool allowBuyOtherNFTs,
        uint256 maxExpectedTokenInput,
        address nftRecipient
    ) external payable whenNotPaused {
        IPair(pair).swapTokenForNFTs(
            nftNum, desiredTokenIds, allowBuyOtherNFTs, maxExpectedTokenInput, nftRecipient, true, msg.sender
        );
    }

    function swapNFTsForToken(
        address pair,
        uint256[] calldata tokenIds,
        uint256 minExpectedTokenOutput,
        address payable tokenRecipient
    ) external whenNotPaused {
        IPair(pair).swapNFTsForToken(tokenIds, minExpectedTokenOutput, tokenRecipient, true, msg.sender);
    }

    function stopWaitlist() public onlyOwner {
        activeWaitlist = false;
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
