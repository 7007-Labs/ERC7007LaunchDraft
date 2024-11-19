// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import {PairType} from "./enums/PairType.sol";
import {PairVariant} from "./enums/PairVariant.sol";
import {IPair} from "./interfaces/IPair.sol";
import {ICurve} from "./interfaces/ICurve.sol";
import {IRoyaltyManager} from "./interfaces/IRoyaltyManager.sol";
import {IPairFactory} from "./interfaces/IPairFactory.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";
import {IORAERC7007} from "./interfaces/IORAERC7007.sol";

contract PairERC7007ETH is IPair, Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using Address for address payable;
    using BitMaps for BitMaps.BitMap;

    uint16 public constant DEFAULT_FEE_BPS = 100;
    uint16 public constant DEFAULT_PROTOCOL_FEE_BPS = 10;

    /// @notice Sales configurateion
    /// @dev Uses 3 storage slots
    struct SalesConfig {
        uint32 maxPresalePurchasePerAddress;
        uint32 presaleMaxNum;
        uint64 presaleStart;
        uint64 presaleEnd;
        uint64 publicSaleStart;
        uint96 initPrice;
        ICurve bondingCurve;
        bytes32 presaleMerkleRoot;
    }

    IPairFactory public immutable factory;
    IRoyaltyManager public immutable royaltyManager;
    IFeeManager public immutable feeManager;

    address public nft;

    address public propertyChecker;
    BitMaps.BitMap private saleOutNFTs;

    uint256 public nextUnIssuedTokenId;
    uint256 public nftTotalSupply;
    SalesConfig public salesConfig;

    mapping(address => uint256) public presalePurchasePerAddress;
    // Events

    event SwapNFTInPair(uint256 amountOut, uint256[] ids);
    event SwapNFTOutPair(uint256 amountIn, uint256[] ids);
    event PresaleMerkleRootUpdate(bytes32 newRoot);

    // Errors
    error TradeFeeTooLarge();
    error ZeroSwapAmount();
    error InputTooLarge();
    error InsufficientInput();
    error TokenIdUnrevealed();
    error NotRouter();
    error OutputTooSmall();
    error PresaleInactive();
    error SaleInactive();
    error PresaleTooManyForAddress();
    error PresaleMerkleNotApproved();
    error SoldOut();

    modifier onlyPresaleActive() {
        if (block.timestamp < salesConfig.presaleStart || block.timestamp >= salesConfig.presaleEnd) {
            revert PresaleInactive();
        }
        _;
    }

    modifier onlyPublicSaleActive() {
        if (block.timestamp < salesConfig.publicSaleStart) {
            revert SaleInactive();
        }
        _;
    }

    constructor(address _factory, address _royaltyManager, address _feeManager) {
        factory = IPairFactory(_factory);
        royaltyManager = IRoyaltyManager(_royaltyManager);
        feeManager = IFeeManager(_feeManager);
        _disableInitializers();
    }

    function initialize(
        address _owner,
        address _nft,
        address _propertyChecker,
        uint256 _nftTotalSupply,
        SalesConfig calldata _salesConfig
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
        bytes32[] calldata merkleProof,
        bool isRouter,
        address routerCaller
    ) external payable nonReentrant onlyPresaleActive returns (uint256 presaleNum, uint256 totalAmount) {
        if (!factory.isRouterAllowed(msg.sender)) revert NotRouter();
        presaleNum = Math.min(nftNum, salesConfig.presaleMaxNum - nextUnIssuedTokenId);
        if (presaleNum == 0) revert SoldOut();

        _checkCanPurchasePresale(isRouter, routerCaller, merkleProof, presaleNum);

        uint256[] memory tokenIds = new uint256[](presaleNum);
        for (uint256 i = 0; i < presaleNum; i++) {
            tokenIds[i] = nextUnIssuedTokenId + i;
        }
        nextUnIssuedTokenId += presaleNum;

        uint256 revealFee = IORAERC7007(nft).estimateRevealFee(presaleNum);
        IORAERC7007(nft).reveal{value: revealFee}(tokenIds);

        uint256 price = salesConfig.initPrice * presaleNum;
        totalAmount = _swapTokenForSpecificNFTs(tokenIds, price, revealFee, maxExpectedTokenInput, nftRecipient);
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

        uint256[] memory tokenIds = new uint256[](nftNum);

        uint256 unIssuedNFTNum = Math.min(nftNum, nftTotalSupply - nextUnIssuedTokenId);
        for (uint256 i = 0; i < unIssuedNFTNum; i++) {
            tokenIds[i] = nextUnIssuedTokenId + i;
        }

        uint256 revealFee = 0;
        if (unIssuedNFTNum > 0) {
            revealFee = IORAERC7007(nft).estimateRevealFee(unIssuedNFTNum);

            nextUnIssuedTokenId += unIssuedNFTNum;
            assembly {
                mstore(tokenIds, unIssuedNFTNum)
            }
            IORAERC7007(nft).reveal{value: revealFee}(tokenIds);
            assembly {
                mstore(tokenIds, nftNum)
            }
        }
        uint256 issuedNFTNum = 0;
        if (unIssuedNFTNum < nftNum) {
            uint256[] memory issuedTokenIds = _selectNFTs(nftNum - unIssuedNFTNum);
            issuedNFTNum = issuedTokenIds.length;
            for (uint256 i = 0; i < issuedNFTNum; i++) {
                tokenIds[i + unIssuedNFTNum] = issuedTokenIds[i];
            }
        }
        totalNFTNum = unIssuedNFTNum + issuedNFTNum;
        if (totalNFTNum == 0) revert SoldOut();
        assembly {
            mstore(tokenIds, totalNFTNum)
        }
        uint256 price = _bondingCurve().getBuyPrice(address(this), totalNFTNum);
        totalAmount = _swapTokenForSpecificNFTs(tokenIds, price, revealFee, maxExpectedTokenInput, nftRecipient);
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
        if (totalNFTNum < minNFTNum) revert OutputTooSmall();
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

        // 计算royalty
        (address payable[] memory royaltyRecipients, uint256[] memory royaltyAmounts, uint256 totalRoyalty) =
            IRoyaltyManager(royaltyManager).calculateRoyalty(address(this), tokenIds[0], outputAmount);

        // 计算Fee
        (address payable[] memory feeRecipients, uint256[] memory feeAmounts, uint256 totalFee) =
            IFeeManager(feeManager).calculateFees(address(this), price);

        // 资产检查
        outputAmount = price - totalFee - totalRoyalty;
        if (outputAmount < minExpectedTokenOutput) {
            revert OutputTooSmall();
        }
        // 转nft
        _takeNFTsFromSender(tokenIds, isRouter, routerCaller);

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
        uint256 revealFee,
        uint256 maxExpectedTokenInput,
        address nftRecipient
    ) internal returns (uint256 totalAmount) {
        // 计算Fee
        (address payable[] memory feeRecipients, uint256[] memory feeAmounts, uint256 totalFee) =
            IFeeManager(feeManager).calculateFees(address(this), price);

        // 计算royalty
        (address payable[] memory royaltyRecipients, uint256[] memory royaltyAmounts, uint256 totalRoyalty) =
            IRoyaltyManager(royaltyManager).calculateRoyalty(address(this), tokenIds[0], price);

        // 资产检查
        totalAmount = price + totalFee + totalRoyalty + revealFee;
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
        uint256 nftNum = tokenIds.length;
        for (uint256 i = 0; i < nftNum; i++) {
            uint256 tokenId = tokenIds[i];
            if (tokenId >= nextUnIssuedTokenId) revert TokenIdUnrevealed();
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

    function _checkCanPurchasePresale(
        bool isRouter,
        address routerCaller,
        bytes32[] calldata merkleProof,
        uint256 quantity
    ) internal {
        address _from = isRouter ? routerCaller : msg.sender;
        presalePurchasePerAddress[_from] += quantity;
        if (presalePurchasePerAddress[_from] > salesConfig.maxPresalePurchasePerAddress) {
            revert PresaleTooManyForAddress();
        }

        bytes32 leaf = keccak256(abi.encodePacked(_from));

        if (!MerkleProof.verifyCalldata(merkleProof, salesConfig.presaleMerkleRoot, leaf)) {
            revert PresaleMerkleNotApproved();
        }
    }

    function _selectNFTs(
        uint256 num
    ) internal view returns (uint256[] memory tokenIds) {
        tokenIds = new uint256[](num);
        uint256 mod = nextUnIssuedTokenId;
        // 随机选择开始查询的tokenId
        uint256 start = block.number % mod;
        uint256 count = 0;
        for (uint256 i = 0; i < nextUnIssuedTokenId; i++) {
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

    function _takeNFTsFromSender(uint256[] calldata tokenIds, bool isRouter, address routerCaller) internal {
        address _from = isRouter ? routerCaller : msg.sender;
        for (uint256 i = 0; i < tokenIds.length; i++) {
            saleOutNFTs.setTo(tokenIds[i], false);
            IERC721(nft).transferFrom(_from, address(this), tokenIds[i]);
        }
    }

    function _bondingCurve() internal view returns (ICurve) {
        return salesConfig.bondingCurve;
    }

    function getPresaleQuote(
        uint256 assetId,
        uint256 numItems
    ) external view returns (uint256 inputAmount, uint256 revealFee, uint256 royaltyAmount) {
        revealFee = IORAERC7007(nft).estimateRevealFee(numItems);
        uint256 price = salesConfig.initPrice * numItems;
        (,, uint256 totalFee) = IFeeManager(feeManager).calculateFees(address(this), price);

        // 计算royalty
        (,, uint256 royaltyAmount_) = IRoyaltyManager(royaltyManager).calculateRoyalty(address(this), assetId, price);
        royaltyAmount = royaltyAmount_;
        inputAmount = price + totalFee + royaltyAmount;
    }

    function getBuyNFTQuote(
        uint256 assetId,
        uint256 numItems,
        bool isPick
    ) external view returns (uint256 inputAmount, uint256 revealFee, uint256 royaltyAmount) {
        uint256 unRevealedNFTNum;
        if (!isPick) {
            unRevealedNFTNum = Math.min(numItems, nftTotalSupply - nextUnIssuedTokenId);
            revealFee = IORAERC7007(nft).estimateRevealFee(unRevealedNFTNum);
        }
        uint256 price = _bondingCurve().getBuyPrice(address(this), numItems);

        (,, uint256 totalFee) = IFeeManager(feeManager).calculateFees(address(this), price);

        // 计算royalty
        (,, uint256 royaltyAmount_) = IRoyaltyManager(royaltyManager).calculateRoyalty(address(this), assetId, price);
        royaltyAmount = royaltyAmount_;
        inputAmount = price + totalFee + royaltyAmount;
    }

    function getSellNFTQuote(
        uint256 assetId,
        uint256 numItems
    ) external view returns (uint256 outputAmount, uint256 royaltyAmount) {
        uint256 price = _bondingCurve().getSellPrice(address(this), numItems);
        // 计算Fee
        (, uint256[] memory feeAmounts, uint256 totalFee) = IFeeManager(feeManager).calculateFees(address(this), price);

        outputAmount = price - totalFee;
        (,, uint256 royaltyAmount_) =
            IRoyaltyManager(royaltyManager).calculateRoyalty(address(this), assetId, outputAmount);
        royaltyAmount = royaltyAmount_;
        outputAmount -= royaltyAmount;
    }

    function setPresalwMerkleRoot(
        bytes32 newRoot
    ) public onlyOwner {
        require(block.timestamp < salesConfig.presaleStart, "Presale has already started");
        salesConfig.presaleMerkleRoot = newRoot;
        emit PresaleMerkleRootUpdate(newRoot);
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
