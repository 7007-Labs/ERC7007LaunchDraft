// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {PairType} from "./enums/PairType.sol";
import {PairVariant} from "./enums/PairVariant.sol";
import {IPair} from "./interfaces/IPair.sol";
import {ICurve} from "./interfaces/ICurve.sol";
import {ITotalSupply} from "./interfaces/ITotalSupply.sol";
import {IRoyaltyManager} from "./interfaces/IRoyaltyManager.sol";
import {IPairFactory} from "./interfaces/IPairFactory.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";
import {ITransferManager} from "./interfaces/ITransferManager.sol";
import {IORAERC7007} from "./interfaces/IORAERC7007.sol";

contract PairERC7007ETH is IPair, Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using Address for address payable;
    using BitMaps for BitMaps.BitMap;

    IPairFactory public immutable factory;
    IRoyaltyManager public immutable royaltyManager;
    IFeeManager public immutable feeManager;
    ITransferManager public immutable transferManager;

    address public nft;
    ICurve public bondingCurve;
    address public propertyChecker;
    BitMaps.BitMap private saleOutNFTs;

    uint256 public nextUnrevealedTokenId;
    uint256 public nftTotalSupply;
    uint16 public constant defaultFeeBPS = 0;
    uint16 public constant defaultProtocolFeeBPS = 10;

    // Events
    event SwapNFTInPair(uint256 amountOut, uint256[] ids);
    event SwapNFTOutPair(uint256 amountIn, uint256[] ids);

    // Errors
    error TradeFeeTooLarge();
    error ZeroSwapAmount();
    error InputTooLarge();
    error InsufficientInput();
    error TokenIdUnrevealed();
    error NotRouter();
    error OutputTooSmall();

    constructor(address _factory, address _royaltyManager, address _feeManager, address _transferManager) {
        factory = IPairFactory(_factory);
        royaltyManager = IRoyaltyManager(_royaltyManager);
        feeManager = IFeeManager(_feeManager);
        transferManager = ITransferManager(_transferManager);
        _disableInitializers();
    }

    function initialize(
        address _owner,
        address _nft,
        ICurve _bondingCurve,
        address _propertyChecker,
        uint256 _nftTotalSupply
    ) external initializer {
        __Ownable_init(_owner);
        nft = _nft;
        bondingCurve = _bondingCurve;
        propertyChecker = _propertyChecker;
        nftTotalSupply = _nftTotalSupply;
        feeManager.register(_owner, defaultFeeBPS, defaultProtocolFeeBPS);
    }

    function _swapTokenForSpecificNFTs(
        uint256[] memory tokenIds,
        uint256 aigcAmount,
        uint256 maxExpectedTokenInput,
        address nftRecipient
    ) internal returns (uint256 totalAmount) {
        uint256 nftNum = tokenIds.length;
        // 计算价格
        uint256 price = ICurve(bondingCurve).getBuyPrice(address(this), nftNum);

        // 计算Fee
        (address payable[] memory feeRecipients, uint256[] memory feeAmounts) =
            IFeeManager(feeManager).calculateFees(address(this), price);
        uint256 totalFee = 0;
        for (uint256 i = 0; i < feeRecipients.length; i++) {
            totalFee += feeAmounts[i];
        }

        // 计算royalty
        (address payable[] memory royaltyRecipients, uint256[] memory royaltyAmounts) =
            IRoyaltyManager(royaltyManager).calculateRoyaltyFee(address(this), tokenIds[0], price);
        uint256 totalRoyalty = 0;
        for (uint256 i = 0; i < royaltyRecipients.length; i++) {
            totalRoyalty += royaltyAmounts[i];
        }

        // 资产检查
        totalAmount = price + totalFee + totalRoyalty + aigcAmount;
        if (totalAmount > maxExpectedTokenInput) {
            revert InputTooLarge();
        }
        if (msg.value < totalAmount) {
            revert InsufficientInput();
        }

        // 转token
        for (uint256 i = 0; i < feeRecipients.length; i++) {
            feeRecipients[i].sendValue(feeAmounts[i]);
        }

        for (uint256 i = 0; i < royaltyRecipients.length; i++) {
            royaltyRecipients[i].sendValue(royaltyAmounts[i]);
        }

        // 转nft
        for (uint256 i = 0; i < nftNum; i++) {
            uint256 tokenId = tokenIds[i];
            if (tokenId >= nextUnrevealedTokenId) revert TokenIdUnrevealed();
            saleOutNFTs.set(tokenId);
            IERC721(nft).transferFrom(address(this), nftRecipient, tokenId);
        }
        // 返还多余金额
        _refundTokenToSender(totalAmount);

        emit SwapNFTOutPair(totalAmount, tokenIds);
    }

    function swapTokenForNFTs(
        uint256 nftNum,
        uint256 maxExpectedTokenInput,
        address nftRecipient,
        bool isRouter,
        address /* routerCaller */
    ) external payable nonReentrant returns (uint256, uint256) {
        require(isRouter, "Only Router");

        if (!factory.isRouterAllowed(msg.sender)) revert NotRouter();

        if (nftNum == 0) revert ZeroSwapAmount();
        uint256[] memory tokenIds;
        uint256 aigcAmount = 0;
        uint256 totalNFTNum = 0;

        tokenIds = new uint256[](nftNum);
        uint256 unrevealedNFTNum = Math.min(nftNum, nftTotalSupply - nextUnrevealedTokenId);

        for (uint256 i = 0; i < unrevealedNFTNum; i++) {
            tokenIds[i] = nextUnrevealedTokenId + i;
        }
        if (unrevealedNFTNum > 0) {
            nextUnrevealedTokenId += unrevealedNFTNum;
            assembly {
                mstore(tokenIds, unrevealedNFTNum)
            }
            IORAERC7007(nft).reveal{value: aigcAmount}(tokenIds);
            assembly {
                mstore(tokenIds, nftNum)
            }
        }
        uint256 revealedNFTNum = 0;
        if (unrevealedNFTNum < nftNum) {
            uint256[] memory revealedTokenIds = _selectNFTs(nftNum - unrevealedNFTNum);
            revealedNFTNum = revealedTokenIds.length;
            for (uint256 i = 0; i < revealedNFTNum; i++) {
                tokenIds[i + unrevealedNFTNum] = revealedTokenIds[i];
            }
        }
        totalNFTNum = unrevealedNFTNum + unrevealedNFTNum;

        assembly {
            mstore(tokenIds, totalNFTNum)
        }
        uint256 totalAmount = _swapTokenForSpecificNFTs(tokenIds, aigcAmount, maxExpectedTokenInput, nftRecipient);
        return (totalNFTNum, totalAmount);
    }

    function swapTokenForSpecificNFTs(
        uint256[] calldata targetTokenIds,
        bool allowAlternative,
        uint256 maxExpectedTokenInput,
        address nftRecipient,
        bool, /* isRouter */
        address /* routerCaller */
    ) external payable nonReentrant returns (uint256, uint256) {
        uint256 targetNFTNum = targetTokenIds.length;
        if (targetNFTNum == 0) revert ZeroSwapAmount();

        uint256[] memory tokenIds = new uint256[](targetNFTNum);
        uint256 totalNFTNum = 0;

        for (uint256 i = 0; i < targetNFTNum; i++) {
            uint256 tokenId = targetTokenIds[i];
            if (saleOutNFTs.get(tokenId)) continue;
            tokenIds[totalNFTNum] = tokenId;
            totalNFTNum += 1;
        }
        if (totalNFTNum < targetNFTNum && allowAlternative) {
            uint256[] memory newTokenIds = _selectNFTs(targetNFTNum - totalNFTNum);
            for (uint256 i = 0; i < newTokenIds.length; i++) {
                tokenIds[totalNFTNum] = newTokenIds[i];
                totalNFTNum += 1;
            }
        }
        assembly {
            mstore(tokenIds, totalNFTNum)
        }
        uint256 totalAmount = _swapTokenForSpecificNFTs(tokenIds, 0, maxExpectedTokenInput, nftRecipient);

        return (totalNFTNum, totalAmount);
    }

    function _refundTokenToSender(
        uint256 inputAmount
    ) internal {
        if (msg.value > inputAmount) {
            payable(msg.sender).sendValue(msg.value - inputAmount);
        }
    }

    function _selectNFTs(
        uint256 num
    ) internal view returns (uint256[] memory tokenIds) {
        tokenIds = new uint256[](num);
        uint256 mod = nextUnrevealedTokenId;
        // 随机选择开始查询的tokenId
        uint256 start = block.number % mod;
        uint256 count = 0;
        for (uint256 i = 0; i < nextUnrevealedTokenId; i++) {
            uint256 tokenId = (start + i) % mod;
            if (saleOutNFTs.get(tokenId)) continue;
            tokenIds[count] = tokenId;
            count += 1;
            if (count == num) break;
        }
        assembly {
            mstore(tokenIds, count)
        }
    }

    function swapNFTsForToken(
        uint256[] calldata tokenIds,
        uint256 minExpectedTokenOutput,
        address payable tokenRecipient,
        bool isRouter,
        address routerCaller
    ) external nonReentrant returns (uint256 outputAmount) {
        require(isRouter, "Only Router");
        if (!factory.isRouterAllowed(msg.sender)) revert NotRouter();

        if (tokenIds.length == 0) revert ZeroSwapAmount();
        uint256 price = ICurve(bondingCurve).getSellPrice(address(this), tokenIds.length);
        // 计算Fee
        (address payable[] memory feeRecipients, uint256[] memory feeAmounts) =
            IFeeManager(feeManager).calculateFees(address(this), price);
        uint256 totalFee = 0;
        for (uint256 i = 0; i < feeRecipients.length; i++) {
            totalFee += feeAmounts[i];
        }

        outputAmount = price - totalFee;
        // 计算royalty
        (address payable[] memory royaltyRecipients, uint256[] memory royaltyAmounts) =
            IRoyaltyManager(royaltyManager).calculateRoyaltyFee(address(this), tokenIds[0], outputAmount);

        uint256 totalRoyalty = 0;
        for (uint256 i = 0; i < royaltyRecipients.length; i++) {
            totalRoyalty += royaltyAmounts[i];
        }

        // 资产检查
        outputAmount -= totalRoyalty;
        if (outputAmount < minExpectedTokenOutput) {
            revert OutputTooSmall();
        }
        // 转nft
        _takeNFTsFromSender(nft, tokenIds, isRouter, routerCaller);

        // 转token
        tokenRecipient.sendValue(outputAmount);

        for (uint256 i = 0; i < feeRecipients.length; i++) {
            feeRecipients[i].sendValue(feeAmounts[i]);
        }

        for (uint256 i = 0; i < royaltyRecipients.length; i++) {
            royaltyRecipients[i].sendValue(royaltyAmounts[i]);
        }
        emit SwapNFTInPair(outputAmount, tokenIds);
    }

    function _takeNFTsFromSender(
        address _nft,
        uint256[] calldata tokenIds,
        bool isRouter,
        address routerCaller
    ) internal {
        address _from = isRouter ? routerCaller : msg.sender;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            saleOutNFTs.setTo(tokenIds[i], false);
            transferManager.transferERC721(_nft, _from, address(this), tokenIds);
        }
    }

    function getBuyNFTQuote(
        uint256 assetId,
        uint256 numItems,
        bool isPick // 是否选购
    ) external view returns (uint256 inputAmount, uint256 aigcAmount, uint256 royaltyAmount) {
        uint256 unRevealedNFTNum;
        if (!isPick) {
            unRevealedNFTNum = Math.min(numItems, nftTotalSupply - nextUnrevealedTokenId);
            aigcAmount = IORAERC7007(nft).estimateFee(unRevealedNFTNum);
        }
        uint256 price = ICurve(bondingCurve).getBuyPrice(address(this), numItems);

        (, uint256[] memory feeAmounts) = IFeeManager(feeManager).calculateFees(address(this), price);
        uint256 totalFee = 0;
        for (uint256 i = 0; i < feeAmounts.length; i++) {
            totalFee += feeAmounts[i];
        }

        // 计算royalty
        (, uint256[] memory royaltyAmounts) =
            IRoyaltyManager(royaltyManager).calculateRoyaltyFee(address(this), assetId, price);

        for (uint256 i = 0; i < royaltyAmounts.length; i++) {
            royaltyAmount += royaltyAmounts[i];
        }
        inputAmount = price + totalFee + royaltyAmount;
    }

    function getSellNFTQuote(
        uint256 assetId,
        uint256 numItems
    ) external view returns (uint256 outputAmount, uint256 royaltyAmount) {
        uint256 price = ICurve(bondingCurve).getSellPrice(address(this), numItems);
        // 计算Fee
        (, uint256[] memory feeAmounts) = IFeeManager(feeManager).calculateFees(address(this), price);

        uint256 totalFee = 0;
        for (uint256 i = 0; i < feeAmounts.length; i++) {
            totalFee += feeAmounts[i];
        }
        outputAmount = price - totalFee;
        (, uint256[] memory royaltyAmounts) =
            IRoyaltyManager(royaltyManager).calculateRoyaltyFee(address(this), assetId, outputAmount);

        for (uint256 i = 0; i < royaltyAmounts.length; i++) {
            royaltyAmount += royaltyAmounts[i];
        }
        outputAmount -= royaltyAmount;
    }

    function syncNFTStatus(
        uint256 tokenId
    ) external nonReentrant {
        require(tokenId < nftTotalSupply);
        bool isOwner = IERC721(nft).ownerOf(tokenId) == address(this);
        saleOutNFTs.setTo(tokenId, !isOwner);
    }

    function owner() public view override(IPair, OwnableUpgradeable) returns (address) {
        return super.owner();
    }

    function token() external pure returns (address) {
        return address(0);
    }

    function pairType() external pure returns (PairType) {
        return PairType.LAUNCH;
    }

    function pairVariant() external pure returns (PairVariant) {
        return PairVariant.ERC7007_ETH;
    }
}
