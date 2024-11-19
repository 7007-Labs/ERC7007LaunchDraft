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

/**
 * @title ERC7007Launch
 * @notice Contract for launching ERC7007 NFT collections.
 */
contract ERC7007Launch is Whitelist, Initializable, OwnableUpgradeable, UUPSUpgradeable, PausableUpgradeable {
    /// @notice Params for NFT Collection launching
    struct LaunchParams {
        /// @notice Initialization data for NFT
        /// @dev Encoded metadata (name, symbol, description, nsfw)
        bytes metadataInitializer;
        /// @notice The prompt text used to generate NFT
        string prompt;
        /// @dev The identifier of AIGC provider
        address provider;
        /// @dev Addition parameters passed to the provider
        bytes providerParams;
        /// @notice The address of the bonding curve contract
        address bondingCurve;
        /// @notice The initial number of NFTs that can be purchased at launch
        uint256 initialBuyNum;
        /// @notice The fixed price during presale period
        uint96 initialPrice;
        /// @notice Maximum total NFTs that can be purchased during presale
        uint32 presaleMaxNum;
        /// @notice Presale start timestamp
        uint64 preSaleStart;
        /// @notice Presale end timestamp
        /// @dev set to 0 to disable presale
        uint64 preSaleEnd;
        /// @notice Merkle root for verifying presale eligibility
        bytes32 presaleMerkleRoot;
    }

    uint64 public constant NFT_TOTAL_SUPPLY = 7007;
    uint64 public constant MAX_INIT_BUY_NUM = 10;
    uint32 public constant MAX_PRESALE_PER_ADDRESS = 1;

    address public immutable nftCollectionFactory;
    address public immutable pairFactory;

    bool public isEnableWhitelist;

    event WhitelistMerkleRootUpdated(bytes32 newRoot);
    event WhitelistStateChanged(bool isEnabled);

    error InvalidInitialBuyNum();

    /**
     * @dev Constructor to set immutable addresses
     * @param _nftCollectionFactory Address of the NFT collection factory
     * @param _pairFactory Address of the pair factory
     */
    constructor(address _nftCollectionFactory, address _pairFactory) {
        nftCollectionFactory = _nftCollectionFactory;
        pairFactory = _pairFactory;
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with an owner and enables whitelist by default
     * @param owner Address to be set as the contract owner
     */
    function initialize(
        address owner
    ) external initializer {
        __Ownable_init(owner);
        __Pausable_init();
        isEnableWhitelist = true;
    }

    /**
     * @dev Launches a new NFT collection with trading pair
     * @param params LaunchParams struct containing all necessary parameters
     * @param whitelistProof Proof for launch whitelist verification
     * @notice Creates NFT collection, sets up trading pair, and performs initial buy
     */
    function launch(LaunchParams calldata params, bytes32[] calldata whitelistProof) external payable whenNotPaused {
        if (params.initialBuyNum == 0 || params.initialBuyNum > MAX_INIT_BUY_NUM) revert InvalidInitialBuyNum();
        _checkWhitelist(whitelistProof);

        address collection = INFTCollectionFactory(nftCollectionFactory).createNFTCollection(
            msg.sender, params.prompt, params.metadataInitializer, params.provider, params.providerParams
        );

        IPair.SalesConfig memory salesConfig = IPair.SalesConfig({
            maxPresalePurchasePerAddress: MAX_PRESALE_PER_ADDRESS,
            presaleMaxNum: params.presaleMaxNum,
            presaleStart: params.preSaleStart,
            presaleEnd: params.preSaleEnd,
            publicSaleStart: params.preSaleEnd,
            initialPrice: params.initialPrice,
            bondingCurve: ICurve(params.bondingCurve),
            presaleMerkleRoot: params.presaleMerkleRoot
        });

        bytes memory data = abi.encode(NFT_TOTAL_SUPPLY, salesConfig);

        // Create trading pair
        address pair = IPairFactory(pairFactory).createPairERC7007ETH(
            msg.sender,
            collection,
            PairType.LAUNCH,
            address(0), // No property checker needed
            data
        );

        // Activate NFT collection
        IORAERC7007(collection).activate(NFT_TOTAL_SUPPLY, pair, pair);

        // Perform initial NFT purchase
        IPair(pair).swapTokenForNFTs(params.initialBuyNum, msg.value, msg.sender, true, msg.sender);
    }

    /**
     * @dev Purchases NFTs during presale period
     * @param pair Address of the trading pair
     * @param nftNum Number of NFTs to purchase
     * @param maxExpectedTokenInput Maximum amount of tokens willing to spend
     * @param nftRecipient Address to receive the NFTs
     * @param whitelistProof Proof for launch whitelist verification
     * @param presaleMerkleProof Proof for presale whitelist verification
     * @return tokenInputAmount Amount of tokens spent
     * @return protocolFee Protocol fee charged
     */
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

    /**
     * @notice Swaps tokens for NFTs
     * @param pair Address of the trading pair
     * @param nftNum Number of NFTs to purchase
     * @param maxExpectedTokenInput Maximum amount of tokens willing to spend
     * @param nftRecipient Address to receive the NFTs
     * @param whitelistProof Proof for whitelist verification
     * @return tokenInputAmount Amount of tokens spent
     * @return protocolFee Protocol fee charged
     */
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

    /**
     * @dev Swaps tokens for specific NFT IDs
     * @param pair Address of the trading pair
     * @param tokenIds List of specific NFT IDs to purchase
     * @param maxNFTNum Maximum number of NFTs to purchase
     * @param minNFTNum Minimum number of NFTs to purchase
     * @param maxExpectedTokenInput Maximum amount of tokens willing to spend
     * @param nftRecipient Address to receive the NFTs
     * @param whitelistProof Proof for whitelist verification
     * @return tokenInputAmount Amount of tokens spent
     * @return protocolFee Protocol fee charged
     */
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

    /**
     * @dev Swaps NFTs for tokens
     * @param pair Address of the trading pair
     * @param tokenIds List of NFT IDs to sell to the pair
     * @param minExpectedTokenOutput Minimum amount of tokens to receive
     * @param tokenRecipient Address to receive the tokens
     * @param whitelistProof Proof for whitelist verification
     * @return Amount of tokens received
     */
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

    /**
     * @notice Sets the Merkle root for whitelist verification
     * @param root New Merkle root value
     */
    function setWhitelistMerkleRoot(
        bytes32 root
    ) external onlyOwner {
        _setWhitelistMerkleRoot(root);
        emit WhitelistMerkleRootUpdated(root);
    }

    /**
     * @dev Disables whitelist functionality
     */
    function disableWhitelist() public onlyOwner {
        isEnableWhitelist = false;
        emit WhitelistStateChanged(false);
    }

    /**
     * @dev Enables whitelist functionality
     */
    function enableWhitelist() public onlyOwner {
        isEnableWhitelist = true;
        emit WhitelistStateChanged(true);
    }

    /**
     * @dev Pauses all contract operations
     */
    function pause() public onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses all contract operations
     */
    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * @dev Internal function to verify if sender is whitelisted
     * @param proof Merkle proof for whitelist verification
     */
    function _checkWhitelist(
        bytes32[] calldata proof
    ) internal view {
        if (isEnableWhitelist) {
            require(verifyWhitelistAddress(msg.sender, proof), "Address not whitelisted");
        }
    }

    /**
     * @dev Required by UUPS pattern
     */
    function _authorizeUpgrade(
        address
    ) internal override onlyOwner {}
}
