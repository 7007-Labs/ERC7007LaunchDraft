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

    uint16 public constant DEFAULT_FEE_BPS = 0;
    uint16 public constant DEFAULT_PROTOCOL_FEE_BPS = 10;

    IPairFactory public immutable factory;
    IRoyaltyManager public immutable royaltyManager;
    IFeeManager public immutable feeManager;
    ITransferManager public immutable transferManager;

    address public nft;

    address public propertyChecker;
    BitMaps.BitMap private saleOutNFTs;

    uint256 public nextUnrevealedTokenId;
    uint256 public nftTotalSupply;

    mapping(address => uint256) public presalePurchasePerAddress; //每个地址预售时购买的数量
    // Events

    event SwapNFTInPair(uint256 amountOut, uint256[] ids);
    event SwapNFTOutPair(uint256 amountIn, uint256[] ids);

    // Errors
    error TradeFeeTooLarge();
    error ZeroSwapAmount();
    error InputTooLarge();
    error InsufficientInput();
    error TokenIdUnrevealed();
    error RouterOnly();
    error NotRouter();
    error OutputTooSmall();
    error PresaleInactive();
    error SaleInactive();
    error PresaleTooManyForAddress();
    error SoldOut();

    struct SalesConfig {
        uint96 initPrice; //初始价格，预售时采用这个价格
        uint32 maxPresalePurchasePerAddress; //每个msg.sender 最多购买数量
        uint64 presaleStart;
        uint64 presaleEnd; // 值为0表示不启用预售, 左闭右开区间
        ICurve bondingCurve; //公开发售时使用的bondingCurve
        uint64 presaleMaxNum; // 预售最大数量
        bytes32 presaleMerkleRoot; //todo: 预售白名单使用merkle，暂定, 白名单为一次性定好还是可以修改
            // 没有定义公开发售时间范围，公开发售的时间一定要在预售后，暂定presaleEnd为公开发售开始时间
            // 预售阶段只有买没有卖
    }

    SalesConfig public salesConfig;

    modifier onlyPresaleActive() {
        if (block.timestamp < salesConfig.presaleStart || block.timestamp >= salesConfig.presaleEnd) {
            revert PresaleInactive();
        }
        _;
    }

    modifier onlyPublicSaleActive() {
        if (block.timestamp < salesConfig.presaleEnd) {
            revert SaleInactive();
        }
        _;
    }

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
        address _propertyChecker,
        SalesConfig calldata _salesConfig,
        uint256 _nftTotalSupply
    ) external initializer {
        __Ownable_init(_owner);
        require(_nftTotalSupply > 0);
        require(_nft != address(0));
        nft = _nft;
        propertyChecker = _propertyChecker;
        nftTotalSupply = _nftTotalSupply;
        _checkSalesConfig(_salesConfig);
        salesConfig = _salesConfig;

        feeManager.registerPair(_owner, DEFAULT_FEE_BPS, DEFAULT_PROTOCOL_FEE_BPS);
    }

    function _checkSalesConfig(
        SalesConfig calldata _salesConfig
    ) internal view {
        // todo: 检查参数是否合理
        // todo: 如何检查initPrice和preSaleMaxNum是否合理，用bondingCurve, 需要bondingCurve根据preSaleMaxNum计算一个最小的initPrice
    }

    function purchasePresale(
        uint256 nftNum,
        uint256 maxExpectedTokenInput,
        address nftRecipient,
        bytes32[] calldata merkleProof //对应presale白名单功能
    ) external payable nonReentrant onlyPresaleActive returns (uint256, uint256) {
        // 预售是在固定时间内使用了固定价格的购买，对于没有售卖结束的nft，直接转入公开售卖中。
        // todo: 是否限制仅通过erc7007launch来操作, 如果通过erc7007launch，要考虑两边白名单的交互方式(可以调用pair中的isWhitelist(address)方法)
        // todo: 对msg.sender 做白名单检查
        // todo: 采用有多少卖多少的策略, 没加入类似于minTokenOut的限定逻辑

        uint256 presaleNum = Math.min(nftNum, salesConfig.presaleMaxNum - nextUnrevealedTokenId);
        // 处理presaleNum为0的情况
        if (presaleNum == 0) revert SoldOut();

        // 检查是否超过地址购买上限
        // todo: 如果通过erc7007Launch，需要做一定修改
        if (presalePurchasePerAddress[msg.sender] + presaleNum > salesConfig.maxPresalePurchasePerAddress) {
            revert PresaleTooManyForAddress();
        }

        uint256[] memory tokenIds = new uint256[](presaleNum);
        for (uint256 i = 0; i < presaleNum; i++) {
            tokenIds[i] = nextUnrevealedTokenId + i;
        }
        nextUnrevealedTokenId += presaleNum;

        uint256 aigcAmount = IORAERC7007(nft).estimateRevealFee(presaleNum);
        IORAERC7007(nft).reveal{value: aigcAmount}(tokenIds);

        uint256 price = salesConfig.initPrice * presaleNum;
        uint256 totalAmount =
            _swapTokenForSpecificNFTs(tokenIds, price, aigcAmount, maxExpectedTokenInput, nftRecipient);
        return (presaleNum, totalAmount);
    }

    function swapTokenForNFTs(
        uint256 nftNum,
        uint256 maxExpectedTokenInput,
        address nftRecipient,
        bool, /* isRouter */
        address /* routerCaller */
    ) external payable nonReentrant onlyPublicSaleActive returns (uint256 totalNFTNum, uint256 totalAmount) {
        if (!factory.isRouterAllowed(msg.sender)) revert NotRouter();

        if (nftNum == 0) revert ZeroSwapAmount();
        uint256[] memory tokenIds;
        uint256 aigcAmount = 0;

        tokenIds = new uint256[](nftNum);
        uint256 unrevealedNFTNum = Math.min(nftNum, nftTotalSupply - nextUnrevealedTokenId);

        for (uint256 i = 0; i < unrevealedNFTNum; i++) {
            tokenIds[i] = nextUnrevealedTokenId + i;
        }
        if (unrevealedNFTNum > 0) {
            aigcAmount = IORAERC7007(nft).estimateRevealFee(unrevealedNFTNum);

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
        if (totalNFTNum == 0) revert SoldOut();
        assembly {
            mstore(tokenIds, totalNFTNum)
        }
        uint256 price = _bondingCurve().getBuyPrice(address(this), totalNFTNum);
        totalAmount = _swapTokenForSpecificNFTs(tokenIds, price, aigcAmount, maxExpectedTokenInput, nftRecipient);
    }

    function swapTokenForSpecificNFTs(
        uint256[] calldata targetTokenIds,
        uint256 maxNFTNum,
        uint256 minNFTNum,
        uint256 maxExpectedTokenInput,
        address nftRecipient,
        bool isRouter,
        address /* routerCaller */
    ) external payable nonReentrant onlyPublicSaleActive returns (uint256 totalNFTNum, uint256 totalAmount) {
        if (!factory.isRouterAllowed(msg.sender)) revert NotRouter();

        uint256 targetNFTNum = targetTokenIds.length;
        if (targetNFTNum == 0) revert ZeroSwapAmount();

        uint256[] memory tokenIds = new uint256[](targetNFTNum);

        for (uint256 i = 0; i < targetNFTNum; i++) {
            uint256 tokenId = targetTokenIds[i];
            if (saleOutNFTs.get(tokenId)) continue;
            tokenIds[totalNFTNum] = tokenId;
            totalNFTNum += 1;
        }

        if (totalNFTNum < maxNFTNum) {
            uint256[] memory newTokenIds = _selectNFTs(maxNFTNum - totalNFTNum);
            for (uint256 i = 0; i < newTokenIds.length; i++) {
                tokenIds[totalNFTNum] = newTokenIds[i];
                totalNFTNum += 1;
            }
        }
        if (totalNFTNum == 0) revert SoldOut();

        assembly {
            mstore(tokenIds, totalNFTNum)
        }
        require(totalNFTNum >= minNFTNum);

        uint256 price = _bondingCurve().getBuyPrice(address(this), totalNFTNum);
        totalAmount = _swapTokenForSpecificNFTs(tokenIds, price, 0, maxExpectedTokenInput, nftRecipient);
    }

    function swapNFTsForToken(
        uint256[] calldata tokenIds,
        uint256 minExpectedTokenOutput,
        address payable tokenRecipient,
        bool isRouter,
        address routerCaller
    ) external nonReentrant onlyPublicSaleActive returns (uint256 outputAmount) {
        if (!factory.isRouterAllowed(msg.sender)) revert NotRouter();

        if (tokenIds.length == 0) revert ZeroSwapAmount();
        uint256 price = _bondingCurve().getSellPrice(address(this), tokenIds.length);
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

    function _swapTokenForSpecificNFTs(
        uint256[] memory tokenIds,
        uint256 price,
        uint256 aigcAmount,
        uint256 maxExpectedTokenInput,
        address nftRecipient
    ) internal returns (uint256 totalAmount) {
        uint256 nftNum = tokenIds.length;
        // 计算价格
        // uint256 price = _bondingCurve().getBuyPrice(address(this), nftNum);

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

    function _bondingCurve() internal view returns (ICurve) {
        return salesConfig.bondingCurve;
    }

    function getBuyNFTQuote(
        uint256 assetId,
        uint256 numItems,
        bool isPick
    ) external view returns (uint256 inputAmount, uint256 aigcAmount, uint256 royaltyAmount) {
        uint256 unRevealedNFTNum;
        if (!isPick) {
            unRevealedNFTNum = Math.min(numItems, nftTotalSupply - nextUnrevealedTokenId);
            aigcAmount = IORAERC7007(nft).estimateRevealFee(unRevealedNFTNum);
        }
        uint256 price = _bondingCurve().getBuyPrice(address(this), numItems);

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
        uint256 price = _bondingCurve().getSellPrice(address(this), numItems);
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
