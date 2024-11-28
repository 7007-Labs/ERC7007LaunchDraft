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
import {IRoyaltyExecutor} from "./interfaces/IRoyaltyExecutor.sol";
import {IPairFactory} from "./interfaces/IPairFactory.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";
import {IORAERC7007} from "./interfaces/IORAERC7007.sol";

/**
 * @title PairERC7007ETH
 * @notice This implements the core swap logic from ERC7007 NFT to ETH
 */
contract PairERC7007ETH is IPair, Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using Address for address payable;
    using BitMaps for BitMaps.BitMap;

    /// @dev Fee in basis points (1%)
    uint16 public constant DEFAULT_FEE_BPS = 100;
    /// @dev Protocol fee in basis points (1%)
    uint16 public constant DEFAULT_PROTOCOL_FEE_BPS = 100;

    IPairFactory public immutable factory;
    IRoyaltyExecutor public immutable royaltyExecutor;
    IFeeManager public immutable feeManager;
    address public immutable oraOracleDelegateCaller;

    address public nft;
    /// @dev Property checker reserved for future functionality
    address public propertyChecker;
    uint256 public nextUnIssuedTokenId;
    uint256 public nftTotalSupply;
    SalesConfig public salesConfig;

    /// @dev address => Number of NFTs purchased during the presale
    mapping(address => uint256) public presalePurchasePerAddress;
    BitMaps.BitMap private saleOutNFTs;

    event SwapNFTInPair(uint256 amountOut, uint256[] ids);
    event SwapNFTOutPair(uint256 amountIn, uint256[] ids);
    event PresaleMerkleRootUpdate(bytes32 newRoot);

    error ZeroAddress();
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

    /**
     * @param _factory Address of the pair factory contract
     * @param _royaltyExecutor Address of the royalty executor contract
     * @param _feeManager Address of the fee manager contract
     * @param _oraOracleDelegateCaller Address of the ORAOracleDelegateCaller contract
     */
    constructor(address _factory, address _royaltyExecutor, address _feeManager, address _oraOracleDelegateCaller) {
        if (_factory == address(0)) revert ZeroAddress();
        if (_royaltyExecutor == address(0)) revert ZeroAddress();
        if (_feeManager == address(0)) revert ZeroAddress();
        if (_oraOracleDelegateCaller == address(0)) revert ZeroAddress();

        factory = IPairFactory(_factory);
        royaltyExecutor = IRoyaltyExecutor(_royaltyExecutor);
        feeManager = IFeeManager(_feeManager);
        oraOracleDelegateCaller = _oraOracleDelegateCaller;
        _disableInitializers();
    }

    /**
     * @notice Initializes the pair contract with NFT collection and sales configuration
     * @param _owner Address that will own this pair contract
     * @param _nft Address of the NFT collection contract
     * @param _propertyChecker Address of the property checker contract
     * @param _nftTotalSupply Total supply of NFTs in the collection
     * @param _salesConfig Initial sales configuration parameters
     */
    function initialize(
        address _owner,
        address _nft,
        address _propertyChecker,
        uint256 _nftTotalSupply,
        SalesConfig calldata _salesConfig
    ) external initializer {
        __Ownable_init(_owner);
        require(_nft != address(0), "Invalid NFT address");
        require(_nftTotalSupply > 0, "Invalid NFT total supply");
        nft = _nft;
        propertyChecker = _propertyChecker;
        nftTotalSupply = _nftTotalSupply;
        _checkSalesConfig(_salesConfig);
        salesConfig = _salesConfig;

        feeManager.registerPair(_owner, DEFAULT_FEE_BPS, DEFAULT_PROTOCOL_FEE_BPS);
    }

    /**
     * @notice Handles NFT purchases during presale period with merkle proof verification
     * @param nftNum Number of NFTs to purchase
     * @param maxExpectedTokenInput Maximum amount of ETH willing to spend
     * @param nftRecipient Address to receive the NFTs
     * @param merkleProof Merkle proof for presale whitelist verification
     * @param isRouter Whether the caller is a router contract
     * @param routerCaller Original caller if called through router
     * @return presaleNum Number of NFTs purchased
     * @return totalAmount Total ETH amount spent
     */
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
        IORAERC7007(nft).reveal{value: revealFee}(tokenIds, oraOracleDelegateCaller);

        uint256 price = salesConfig.presalePrice * presaleNum;
        totalAmount = _swapTokenForSpecificNFTs(tokenIds, price, revealFee, maxExpectedTokenInput, nftRecipient);
    }

    /**
     * @notice Swaps tokens for NFTs during public sale
     * @param nftNum Number of NFTs to purchase
     * @param maxExpectedTokenInput Maximum amount of ETH willing to spend
     * @param nftRecipient Address to receive the NFTs
     * @return totalNFTNum Number of NFTs purchased
     * @return totalAmount Total ETH amount spent
     */
    function swapTokenForNFTs(
        uint256 nftNum,
        uint256 maxExpectedTokenInput,
        address nftRecipient,
        bool, /*isRouter*/
        address /*routerCaller*/
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
            IORAERC7007(nft).reveal{value: revealFee}(tokenIds, oraOracleDelegateCaller);
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
        uint256 price = _bondingCurve().getBuyPrice(_totalSupply(), totalNFTNum);
        totalAmount = _swapTokenForSpecificNFTs(tokenIds, price, revealFee, maxExpectedTokenInput, nftRecipient);
    }

    /**
     * @notice Swaps tokens for specific NFT IDs during public sale
     * @param targetTokenIds List of specific NFT IDs to purchase
     * @param expectedNFTNum Expected number of NFTs to purchase
     * @param minNFTNum Minimum number of NFTs to purchase
     * @param maxExpectedTokenInput Maximum amount of ETH willing to spend
     * @param nftRecipient Address to receive the NFTs
     * @return totalNFTNum Number of NFTs purchased
     * @return totalAmount Total ETH amount spent
     */
    function swapTokenForSpecificNFTs(
        uint256[] calldata targetTokenIds,
        uint256 expectedNFTNum,
        uint256 minNFTNum,
        uint256 maxExpectedTokenInput,
        address nftRecipient,
        bool, /*isRouter*/
        address /*routerCaller*/
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

        if (totalNFTNum < expectedNFTNum) {
            uint256[] memory newTokenIds = _selectNFTs(expectedNFTNum - totalNFTNum);
            for (uint256 i = 0; i < newTokenIds.length; i++) {
                tokenIds[totalNFTNum] = newTokenIds[i];
                totalNFTNum += 1;
            }
        }
        if (totalNFTNum == 0) revert SoldOut();

        assembly {
            mstore(tokenIds, totalNFTNum)
        }
        if (totalNFTNum < minNFTNum) revert OutputTooSmall();

        uint256 price = _bondingCurve().getBuyPrice(_totalSupply(), totalNFTNum);
        totalAmount = _swapTokenForSpecificNFTs(tokenIds, price, 0, maxExpectedTokenInput, nftRecipient);
    }

    /**
     * @notice Sends a set of NFTs to the pair in exchange for token
     * @param tokenIds List of NFT IDs to sell to the pair
     * @param minExpectedTokenOutput Minimum amount of ETH to receive
     * @param tokenRecipient Address to receive the ETH
     * @param isRouter Whether the caller is a router contract
     * @param routerCaller Original caller if called through router
     * @return outputAmount Amount of ETH received
     */
    function swapNFTsForToken(
        uint256[] calldata tokenIds,
        uint256 minExpectedTokenOutput,
        address payable tokenRecipient,
        bool isRouter,
        address routerCaller
    ) external nonReentrant onlyPublicSaleActive returns (uint256 outputAmount) {
        if (!factory.isRouterAllowed(msg.sender)) revert NotRouter();

        if (tokenIds.length == 0) revert ZeroSwapAmount();

        address payable[] memory feeRecipients;
        uint256[] memory feeAmounts;

        // used for stack too deep
        {
            uint256 price = _bondingCurve().getSellPrice(_totalSupply(), tokenIds.length);
            uint256 totalFee;
            (feeRecipients, feeAmounts, totalFee) = IFeeManager(feeManager).calculateFees(address(this), price);
            outputAmount = price - totalFee;
        }

        (address payable[] memory royaltyRecipients, uint256[] memory royaltyAmounts, uint256 totalRoyalty) =
            IRoyaltyExecutor(royaltyExecutor).calculateRoyalty(address(this), tokenIds[0], outputAmount);

        outputAmount -= totalRoyalty;
        if (outputAmount < minExpectedTokenOutput) {
            revert OutputTooSmall();
        }
        _takeNFTsFromSender(tokenIds, isRouter, routerCaller);

        tokenRecipient.sendValue(outputAmount);

        for (uint256 i = 0; i < feeRecipients.length; i++) {
            feeRecipients[i].sendValue(feeAmounts[i]);
        }

        for (uint256 i = 0; i < royaltyRecipients.length; i++) {
            royaltyRecipients[i].sendValue(royaltyAmounts[i]);
        }
        emit SwapNFTInPair(outputAmount, tokenIds);
    }

    /**
     * @notice Updates presale merkle root before presale starts
     * @param newRoot New merkle root for presale whitelist
     */
    function setPresaleMerkleRoot(
        bytes32 newRoot
    ) public onlyOwner {
        require(block.timestamp < salesConfig.presaleStart, "Presale has already started");
        salesConfig.presaleMerkleRoot = newRoot;
        emit PresaleMerkleRootUpdate(newRoot);
    }

    /**
     * @notice Syncs NFT sale status
     * @param tokenId ID of NFT to update status for
     */
    function syncNFTStatus(
        uint256 tokenId
    ) external nonReentrant {
        require(tokenId < nftTotalSupply);
        bool isOwner = IERC721(nft).ownerOf(tokenId) == address(this);
        saleOutNFTs.setTo(tokenId, !isOwner);
    }

    /**
     * @notice Calculates total cost for presale purchase
     * @param assetId NFT ID for royalty calculation
     * @param numItems Number of NFTs to purchase
     * @return inputAmount Total ETH required
     * @return revealFee Fee for revealing NFTs
     * @return royaltyAmount Royalty amount
     */
    function getPresaleQuote(
        uint256 assetId,
        uint256 numItems
    ) external view returns (uint256 inputAmount, uint256 revealFee, uint256 royaltyAmount) {
        uint256 price = salesConfig.presalePrice * numItems;

        (,, uint256 totalFee) = IFeeManager(feeManager).calculateFees(address(this), price);

        (,, royaltyAmount) = IRoyaltyExecutor(royaltyExecutor).calculateRoyalty(address(this), assetId, price);

        revealFee = IORAERC7007(nft).estimateRevealFee(numItems);
        inputAmount = price + totalFee + royaltyAmount + revealFee;
    }

    /**
     * @notice Calculates total cost for public sale purchase
     * @param assetId NFT ID for royalty calculation
     * @param numItems Number of NFTs to purchase
     * @param isPick Whether specific NFTs are being selected
     * @return inputAmount Total ETH required
     * @return revealFee Fee for revealing NFTs
     * @return royaltyAmount Royalty amount
     */
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
        uint256 price = _bondingCurve().getBuyPrice(_totalSupply(), numItems);

        (,, uint256 totalFee) = IFeeManager(feeManager).calculateFees(address(this), price);

        (,, royaltyAmount) = IRoyaltyExecutor(royaltyExecutor).calculateRoyalty(address(this), assetId, price);

        inputAmount = price + totalFee + royaltyAmount + revealFee;
    }

    /**
     * @notice Calculates total return for selling NFTs
     * @param assetId NFT ID for royalty calculation
     * @param numItems Number of NFTs to sell
     * @return outputAmount ETH amount to receive
     * @return royaltyAmount Royalty amount
     */
    function getSellNFTQuote(
        uint256 assetId,
        uint256 numItems
    ) external view returns (uint256 outputAmount, uint256 royaltyAmount) {
        uint256 price = _bondingCurve().getSellPrice(_totalSupply(), numItems);
        (,, uint256 totalFee) = IFeeManager(feeManager).calculateFees(address(this), price);

        outputAmount = price - totalFee;
        (,, royaltyAmount) = IRoyaltyExecutor(royaltyExecutor).calculateRoyalty(address(this), assetId, outputAmount);
        outputAmount -= royaltyAmount;
    }

    /**
     * @notice Returns the owner of the pair
     * @return address Current owner address
     */
    function owner() public view override(IPair, OwnableUpgradeable) returns (address) {
        return super.owner();
    }

    /// @dev Returns the token address (0 for ETH)
    function token() external pure returns (address) {
        return address(0);
    }

    function pairType() external pure returns (PairType) {
        return PairType.LAUNCH;
    }

    function pairVariant() external pure returns (PairVariant) {
        return PairVariant.ERC7007_ETH;
    }

    function _checkSalesConfig(
        SalesConfig calldata _salesConfig
    ) internal view {
        /* todo: 检查参数是否合理
         * todo: 如何检查initPrice和preSaleMaxNum是否合理，用bondingCurve, 需要bondingCurve根据preSaleMaxNum计算一个最小的initPrice
         */
    }

    function _swapTokenForSpecificNFTs(
        uint256[] memory tokenIds,
        uint256 price,
        uint256 revealFee,
        uint256 maxExpectedTokenInput,
        address nftRecipient
    ) internal returns (uint256 totalAmount) {
        (address payable[] memory feeRecipients, uint256[] memory feeAmounts, uint256 totalFee) =
            IFeeManager(feeManager).calculateFees(address(this), price);

        (address payable[] memory royaltyRecipients, uint256[] memory royaltyAmounts, uint256 totalRoyalty) =
            IRoyaltyExecutor(royaltyExecutor).calculateRoyalty(address(this), tokenIds[0], price);

        totalAmount = price + totalFee + totalRoyalty + revealFee;

        if (totalAmount > maxExpectedTokenInput) {
            revert InputTooLarge();
        }
        if (msg.value < totalAmount) {
            revert InsufficientInput();
        }

        for (uint256 i = 0; i < feeRecipients.length; i++) {
            feeRecipients[i].sendValue(feeAmounts[i]);
        }

        for (uint256 i = 0; i < royaltyRecipients.length; i++) {
            royaltyRecipients[i].sendValue(royaltyAmounts[i]);
        }

        uint256 nftNum = tokenIds.length;
        for (uint256 i = 0; i < nftNum; i++) {
            uint256 tokenId = tokenIds[i];
            if (tokenId >= nextUnIssuedTokenId) revert TokenIdUnrevealed();
            saleOutNFTs.set(tokenId);
            IERC721(nft).transferFrom(address(this), nftRecipient, tokenId);
        }
        _refundTokenToSender(totalAmount);

        emit SwapNFTOutPair(totalAmount, tokenIds);
    }

    /// @dev Refunds excess ETH to sender
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

        if (
            salesConfig.presaleMerkleRoot != bytes32(0)
                && !MerkleProof.verifyCalldata(merkleProof, salesConfig.presaleMerkleRoot, leaf)
        ) {
            revert PresaleMerkleNotApproved();
        }
    }

    /// @dev Select the NFTs that have already been issued
    function _selectNFTs(
        uint256 num
    ) internal view returns (uint256[] memory tokenIds) {
        tokenIds = new uint256[](num);
        uint256 mod = nextUnIssuedTokenId;
        // use a weak random number, in order to ensure that NFTs with larger IDs can also be selected
        uint256 start = uint256(blockhash(block.number)) % mod;
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

    /// @dev Transfers NFTs from sender to pair contract
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

    function _totalSupply() internal view returns (uint256) {
        return nftTotalSupply - IERC721(nft).balanceOf(address(this));
    }
}
