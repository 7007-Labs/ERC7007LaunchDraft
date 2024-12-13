// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PairType} from "./enums/PairType.sol";
import {OracleGasEstimator} from "./libraries/OracleGasEstimator.sol";
import {INFTCollectionFactory} from "./interfaces/INFTCollectionFactory.sol";
import {IPairFactory} from "./interfaces/IPairFactory.sol";
import {ICurve} from "./interfaces/ICurve.sol";
import {IPair} from "./interfaces/IPair.sol";
import {IRandOracle} from "./interfaces/IRandOracle.sol";
import {IAIOracle} from "./interfaces/IAIOracle.sol";
import {IORAERC7007} from "./interfaces/IORAERC7007.sol";

/**
 * @title ERC7007Launch
 * @notice Contract for launching ERC7007 NFT collections.
 */
contract ERC7007Launch is Initializable, OwnableUpgradeable, UUPSUpgradeable, PausableUpgradeable {
    using Address for address payable;

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
        uint96 presalePrice;
        /// @notice Maximum total NFTs that can be purchased during presale
        uint32 presaleMaxNum;
        /// @notice Presale start timestamp
        uint64 presaleStart;
        /// @notice Presale end timestamp
        /// @dev set to 0 to disable presale
        uint64 presaleEnd;
        /// @notice Merkle root for verifying presale eligibility
        /// @dev set to bytes32(0) to disable verification
        bytes32 presaleMerkleRoot;
    }

    uint64 public constant NFT_TOTAL_SUPPLY = 7007;
    uint32 public constant MAX_PRESALE_PER_ADDRESS = 1;

    address public immutable nftCollectionFactory;
    address public immutable pairFactory;

    error CallerNotWhitelisted();
    error InvalidInitialBuyNum();
    error ZeroAddress();

    /**
     * @dev Constructor to set immutable addresses
     * @param _nftCollectionFactory Address of the NFT collection factory
     * @param _pairFactory Address of the pair factory
     */
    constructor(address _nftCollectionFactory, address _pairFactory) {
        if (_nftCollectionFactory == address(0)) revert ZeroAddress();
        if (_pairFactory == address(0)) revert ZeroAddress();

        nftCollectionFactory = _nftCollectionFactory;
        pairFactory = _pairFactory;
        _disableInitializers();
    }

    /**
     * @dev Initializes the contract with an owner and enables whitelist by default
     * @param _owner Address to be set as the contract owner
     */
    function initialize(
        address _owner
    ) external initializer {
        __Ownable_init(_owner);
        __Pausable_init();
    }

    /// @dev receive refunds from pairs
    receive() external payable {}

    /**
     * @dev Launches a new NFT collection with trading pair
     * @param params LaunchParams struct containing all necessary parameters
     * @return pair Address of the created trading pair
     * @notice Creates NFT collection, sets up trading pair, and performs initial buy
     */
    function launch(
        LaunchParams calldata params
    ) external payable whenNotPaused returns (address pair) {
        require(params.bondingCurve != address(0), "Invalid bonding curve");
        require(params.provider != address(0), "Invalid provider");
        require(params.presaleEnd == 0 || params.presaleEnd > params.presaleStart, "Invalid presale period");
        if (params.presaleEnd > 0) {
            require(params.presaleMaxNum > 0 && params.presaleMaxNum < NFT_TOTAL_SUPPLY, "Invalid presale max num");
        }

        address collection = INFTCollectionFactory(nftCollectionFactory).createNFTCollection(
            msg.sender, params.prompt, params.metadataInitializer, params.provider, params.providerParams
        );

        IPair.SalesConfig memory salesConfig = IPair.SalesConfig({
            maxPresalePurchasePerAddress: MAX_PRESALE_PER_ADDRESS,
            presaleMaxNum: params.presaleMaxNum,
            presaleStart: params.presaleStart,
            presaleEnd: params.presaleEnd,
            publicSaleStart: params.presaleEnd,
            presalePrice: params.presalePrice,
            bondingCurve: ICurve(params.bondingCurve),
            presaleMerkleRoot: params.presaleMerkleRoot
        });

        bytes memory data = abi.encode(NFT_TOTAL_SUPPLY, salesConfig);

        // Create trading pair
        pair = IPairFactory(pairFactory).createPairERC7007ETH(
            msg.sender,
            collection,
            PairType.LAUNCH,
            address(0), // No property checker needed
            data
        );

        // Activate NFT collection
        IORAERC7007(collection).activate(NFT_TOTAL_SUPPLY, pair, pair);

        // non presale model
        if (params.presaleEnd == 0) {
            uint256 amount = _initialBuy(pair, params.initialBuyNum);
            _refundTokenToSender(amount);
        }
    }

    /**
     * @dev Purchases NFTs during presale period
     * @param pair Address of the trading pair
     * @param nftNum Number of NFTs to purchase
     * @param maxExpectedTokenInput Maximum amount of tokens willing to spend
     * @param nftRecipient Address to receive the NFTs
     * @param presaleMerkleProof Proof for presale whitelist verification
     * @return purchasedNftNum Number of NFTs purchased
     * @return amount Amount of tokens spent
     */
    function purchasePresaleNFTs(
        address pair,
        uint256 nftNum,
        uint256 maxExpectedTokenInput,
        address nftRecipient,
        bytes32[] calldata presaleMerkleProof
    ) external payable whenNotPaused returns (uint256 purchasedNftNum, uint256 amount) {
        (purchasedNftNum, amount) = IPair(pair).purchasePresale{value: msg.value}(
            nftNum, maxExpectedTokenInput, nftRecipient, presaleMerkleProof, true, msg.sender
        );
        _refundTokenToSender(amount);
    }

    /**
     * @notice Swaps tokens for NFTs
     * @param pair Address of the trading pair
     * @param nftNum Number of NFTs to purchase
     * @param maxExpectedTokenInput Maximum amount of tokens willing to spend
     * @param nftRecipient Address to receive the NFTs
     * @return purchasedNftNum Number of NFTs purchased
     * @return amount Amount of tokens spent
     */
    function swapTokenForNFTs(
        address pair,
        uint256 nftNum,
        uint256 maxExpectedTokenInput,
        address nftRecipient
    ) external payable whenNotPaused returns (uint256 purchasedNftNum, uint256 amount) {
        (purchasedNftNum, amount) = IPair(pair).swapTokenForNFTs{value: msg.value}(
            nftNum, maxExpectedTokenInput, nftRecipient, true, msg.sender
        );

        _refundTokenToSender(amount);
    }

    /**
     * @dev Swaps tokens for specific NFT IDs
     * @param pair Address of the trading pair
     * @param tokenIds List of specific NFT IDs to purchase
     * @param minNFTNum Minimum number of NFTs to purchase
     * @param maxExpectedTokenInput Maximum amount of tokens willing to spend
     * @param nftRecipient Address to receive the NFTs
     * @return purchasedNftNum Number of NFTs purchased
     * @return amount Amount of tokens spent
     */
    function swapTokenForSpecificNFTs(
        address pair,
        uint256[] calldata tokenIds,
        uint256 minNFTNum,
        uint256 maxExpectedTokenInput,
        address nftRecipient
    ) external payable whenNotPaused returns (uint256 purchasedNftNum, uint256 amount) {
        (purchasedNftNum, amount) = IPair(pair).swapTokenForSpecificNFTs{value: msg.value}(
            tokenIds, minNFTNum, maxExpectedTokenInput, nftRecipient, true, msg.sender
        );
        _refundTokenToSender(amount);
    }

    /**
     * @dev Swaps NFTs for tokens
     * @param pair Address of the trading pair
     * @param tokenIds List of NFT IDs to sell to the pair
     * @param minExpectedTokenOutput Minimum amount of tokens to receive
     * @param tokenRecipient Address to receive the tokens
     * @return Amount of tokens received
     */
    function swapNFTsForToken(
        address pair,
        uint256[] calldata tokenIds,
        uint256 minExpectedTokenOutput,
        address payable tokenRecipient
    ) external whenNotPaused returns (uint256) {
        return IPair(pair).swapNFTsForToken(tokenIds, minExpectedTokenOutput, tokenRecipient, true, msg.sender);
    }

    /**
     * @dev Pauses all contract operations
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpauses all contract operations
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Estimates the launch fee based on the provided parameters
     * @param params Launch parameters
     * @param aiOracle Address of the AI oracle
     * @param randOracle Address of the random oracle
     * @return Amount of tokens spent
     */
    function estimateLaunchFee(
        LaunchParams calldata params,
        address aiOracle,
        address randOracle
    ) external view returns (uint256) {
        if (params.presaleEnd > 0) return 0;

        if (params.initialBuyNum == 0) revert InvalidInitialBuyNum();
        if (aiOracle == address(0)) revert ZeroAddress();
        if (randOracle == address(0)) revert ZeroAddress();

        uint256 price = ICurve(params.bondingCurve).getBuyPrice(0, params.initialBuyNum);
        // default protocol fee 1% and default pair fee 1%
        // no royalty
        uint256 fee = (price * 100 / 10_000) + (price * 100 / 10_000);

        uint256 promptLength = bytes(params.prompt).length;

        uint64 randOracleGaslimit = OracleGasEstimator.getRandOracleCallbackGasLimit(params.initialBuyNum, promptLength);
        uint256 randOracleFee = IRandOracle(randOracle).estimateFee(0, randOracleGaslimit);

        uint64 aiOracleGaslimit = OracleGasEstimator.getAIOracleCallbackGasLimit(params.initialBuyNum, promptLength);
        uint256 modelId = abi.decode(params.providerParams, (uint256));
        uint256 aiOracleFee = IAIOracle(aiOracle).estimateFeeBatch(modelId, aiOracleGaslimit, params.initialBuyNum);
        return price + fee + randOracleFee + aiOracleFee;
    }

    function _initialBuy(address pair, uint256 num) internal returns (uint256 amount) {
        (, amount) = IPair(pair).swapTokenForNFTs{value: msg.value}(num, msg.value, msg.sender, true, msg.sender);
    }

    /// @dev Refunds excess ETH to sender
    function _refundTokenToSender(
        uint256 inputAmount
    ) internal {
        if (msg.value > inputAmount) {
            payable(msg.sender).sendValue(msg.value - inputAmount);
        }
    }

    /**
     * @dev Required by UUPS pattern
     */
    function _authorizeUpgrade(
        address
    ) internal override onlyOwner {}
}
