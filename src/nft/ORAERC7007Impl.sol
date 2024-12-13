// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC2309} from "@openzeppelin/contracts/interfaces/IERC2309.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ERC721RoyaltyUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721RoyaltyUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {LibBytes} from "@solady/utils/LibBytes.sol";

import {OracleGasEstimator} from "../libraries/OracleGasEstimator.sol";
import {AIOracleCallbackReceiver} from "../libraries/AIOracleCallbackReceiver.sol";
import {RandOracleCallbackReceiver} from "../libraries/RandOracleCallbackReceiver.sol";
import {NFTMetadataRenderer} from "../utils/NFTMetadataRenderer.sol";
import {IAIOracle} from "../interfaces/IAIOracle.sol";
import {IRandOracle} from "../interfaces/IRandOracle.sol";
import {IORAOracleDelegateCaller} from "../interfaces/IORAOracleDelegateCaller.sol";
import {IERC7007} from "../interfaces/IERC7007.sol";
import {IERC7007Updatable} from "../interfaces/IERC7007Updatable.sol";
import {IORAERC7007} from "../interfaces/IORAERC7007.sol";
import {IERC7572} from "../interfaces/IERC7572.sol";

/**
 * @title ORAERC7007Impl
 * @notice Implementation of ERC7007 NFT standard with ORA
 */
contract ORAERC7007Impl is
    ERC721RoyaltyUpgradeable,
    IERC4906,
    IERC2309,
    IERC7572,
    IORAERC7007,
    OwnableUpgradeable,
    AIOracleCallbackReceiver,
    RandOracleCallbackReceiver
{
    using Address for address payable;
    using BitMaps for BitMaps.BitMap;
    using LibBytes for LibBytes.BytesStorage;

    uint256 public constant RAND_ORACLE_MODEL_ID = 0;
    string public constant DEFAULT_IMAGE_URL = "ipfs://xxx"; // TODO: Set default image
    string public constant AIGC_TYPE = "image";
    string public constant PROOF_TYPE = "fraud";

    uint256 public modelId;
    string public description;
    string public basePrompt;
    uint256 public totalSupply;
    address public operator;
    bool public nsfw;

    address private defaultNFTOwner;
    BitMaps.BitMap private _firstOwnershipChange;

    /// @dev prompt => tokenId
    mapping(bytes prompt => uint256) public promptToTokenId;

    /// @dev tokenId => seed
    mapping(uint256 tokenId => uint256) public seedOf;

    /// @dev requestId => tokenIds
    mapping(bytes32 requestId => uint256[]) public requestIdToTokenIds;

    /// @dev tokenId => aiOracleRequestId
    mapping(uint256 tokenId => uint256) public tokenIdToAiOracleRequestId;

    /// @dev tokenId => aigcData
    mapping(uint256 tokenId => LibBytes.BytesStorage) private _aigcDataOf;

    event NewRevealRequest(bytes32 indexed requestId, uint256 randOracleRequestId, address delegateCaller);
    event CallAIOracle(bytes32 indexed requestId, uint256 aiOracleRequestId, address delegateCaller);
    event NotRequestAIOracle(bytes32 indexed requestId, address delegateCaller);

    error UnauthorizedCaller();
    error InsufficientRevealFee();
    error ZeroAddress();
    error EmptyPrompt();
    error AlreadyActivated();
    error InvalidRequestId();
    error InvalidTokenId();
    error EmptyArray();
    error InsufficientBalance();
    error RequestAlreadyProcessed();
    error AigcDataExists();
    error WrongAIOracleCallback();
    error InvalidTotalSupply();
    error InvalidDataLength();
    error InvalidCIDLength();
    error InvalidSeedRange();

    modifier onlySelf() {
        if (msg.sender != address(this)) revert UnauthorizedCaller();
        _;
    }

    constructor(
        IAIOracle _aiOracle,
        IRandOracle _randOracle
    ) AIOracleCallbackReceiver(_aiOracle) RandOracleCallbackReceiver(_randOracle) {
        _disableInitializers();
    }

    /**
     * @notice Initializes the NFT collection
     * @param _owner Owner address of the collection
     * @param prompt Base prompt for AI generation
     * @param metadataInitializer Encoded metadata (name, symbol, description, nsfw)
     * @param _modelId AI model identifier
     */
    function initialize(
        address _owner,
        string calldata prompt,
        bytes calldata metadataInitializer,
        uint256 _modelId
    ) external initializer {
        __ERC721Royalty_init();
        __Ownable_init(_owner);
        _initializeMetadata(metadataInitializer);
        if (bytes(prompt).length == 0) revert EmptyPrompt();

        basePrompt = prompt;
        modelId = _modelId;
    }

    /**
     * @notice Initializes metadata from encoded bytes
     * @param metadataInitializer Encoded metadata
     */
    function _initializeMetadata(
        bytes calldata metadataInitializer
    ) internal {
        (string memory name, string memory symbol, string memory _description, bool _nsfw) =
            abi.decode(metadataInitializer, (string, string, string, bool));

        __ERC721_init(name, symbol);
        description = _description;
        nsfw = _nsfw;
    }

    /**
     * @notice Activates the collection
     * @param _totalSupply Total number of NFTs
     * @param _defaultNFTOwner Initial owner of NFTs
     * @param _operator Address authorized to reveal NFTs
     */
    function activate(uint256 _totalSupply, address _defaultNFTOwner, address _operator) external {
        if (_totalSupply == 0) revert InvalidTotalSupply();
        if (_defaultNFTOwner == address(0)) revert ZeroAddress();
        if (_operator == address(0)) revert ZeroAddress();
        if (totalSupply != 0) revert AlreadyActivated();

        totalSupply = _totalSupply;
        operator = _operator;
        defaultNFTOwner = _defaultNFTOwner;

        _increaseBalance(_defaultNFTOwner, uint128(_totalSupply));
        emit ConsecutiveTransfer(0, _totalSupply - 1, address(0), _defaultNFTOwner);
    }

    /**
     * @notice Reveals NFTs using random seeds
     * @param tokenIds Array of token IDs to reveal
     * @param delegateCaller Contract that will act as proxy to call oracle functions
     * @dev IMPORTANT: Caller MUST ensure:
     * 1. tokenIds array contains no duplicate values
     * 2. all tokenIds have not been processed before calling
     * Failing to meet these requirements may result in unexpected behavior
     */
    function reveal(uint256[] calldata tokenIds, address delegateCaller) external payable {
        if (msg.sender != operator) revert UnauthorizedCaller();
        uint256 size = tokenIds.length;
        if (size == 0) revert EmptyArray();

        bytes32 requestId = keccak256(abi.encodePacked(tokenIds));

        uint256 promptLength = bytes(basePrompt).length;

        uint64 aiOracleGasLimit = OracleGasEstimator.getAIOracleCallbackGasLimit(size, promptLength);
        uint256 aiOracleFee = _estimateAIOracleFee(size, aiOracleGasLimit);

        uint64 randOracleGasLimit = OracleGasEstimator.getRandOracleCallbackGasLimit(size, promptLength);
        uint256 randOracleFee = _estimateRandOracleFee(randOracleGasLimit);

        if (msg.value < randOracleFee + aiOracleFee) revert InsufficientRevealFee();

        uint256 randOracleRequestId = _requestRandOracle(
            delegateCaller,
            randOracleFee,
            abi.encodePacked(requestId),
            address(this),
            randOracleGasLimit,
            abi.encode(requestId, delegateCaller)
        );

        requestIdToTokenIds[requestId] = tokenIds;
        emit NewRevealRequest(requestId, randOracleRequestId, delegateCaller);
    }

    /**
     * @notice Estimates total fee for revealing NFTs
     * @param num Number of NFTs to reveal
     * @return Total fee in wei
     */
    function estimateRevealFee(
        uint256 num
    ) external view returns (uint256) {
        uint256 promptLength = bytes(basePrompt).length;
        uint64 randOracleGasLimit = OracleGasEstimator.getRandOracleCallbackGasLimit(num, promptLength);
        uint64 aiOracleGasLimit = OracleGasEstimator.getAIOracleCallbackGasLimit(num, promptLength);
        // todo: 对fee进行放大，gasprice
        return _estimateAIOracleFee(num, aiOracleGasLimit) + _estimateRandOracleFee(randOracleGasLimit);
    }

    /**
     * @notice Adds AI-generated content to a token
     * @param tokenId Token ID to update
     * @param prompt Generation prompt
     * @param aigcData Generated content
     * @param proof Verification proof
     */
    function addAigcData(
        uint256 tokenId,
        bytes memory prompt,
        bytes memory aigcData,
        bytes memory proof
    ) external onlySelf {
        if (!_aigcDataOf[tokenId].isEmpty()) revert AigcDataExists();
        promptToTokenId[prompt] = tokenId;
        _aigcDataOf[tokenId].set(aigcData);
        emit AigcData(tokenId, prompt, aigcData, proof);
        emit MetadataUpdate(tokenId);
    }

    /**
     * @notice Verifies AI-generated content
     * @param prompt Original prompt
     * @param aigcData Generated content
     * @return bool Verification result
     */
    function verify(
        bytes calldata prompt,
        bytes calldata aigcData,
        bytes calldata /* proof */
    ) external view override returns (bool) {
        uint256 tokenId = promptToTokenId[prompt];
        uint256 aiOracleRequestId = tokenIdToAiOracleRequestId[tokenId];
        bytes memory currentAigcData = _aigcDataOf[tokenId].get();
        return aiOracle.isFinalized(aiOracleRequestId) && keccak256(aigcData) == keccak256(currentAigcData);
    }

    /**
     * @notice Updates AI-generated content
     * @param prompt Generation prompt
     * @param aigcData New content
     */
    function update(bytes memory prompt, bytes memory aigcData) external onlySelf {
        uint256 tokenId = promptToTokenId[prompt];
        _aigcDataOf[tokenId].set(aigcData);

        emit Update(tokenId, prompt, aigcData);
        emit MetadataUpdate(tokenId);
    }

    /**
     * @notice Callback for randOracle responses
     * @param output Random value output
     * @param callbackData Original request data
     */
    function awaitRandOracle(
        uint256, /* randOracleRequestId */
        uint256 output,
        bytes calldata callbackData
    ) external override onlyRandOracleCallback {
        (bytes32 requestId, address delegateCaller) = abi.decode(callbackData, (bytes32, address));
        uint256[] memory tokenIds = requestIdToTokenIds[requestId];
        uint256 size = tokenIds.length;
        if (size == 0) revert InvalidRequestId();

        uint256 baseSeed = output ^ uint256(keccak256(abi.encodePacked(requestId, block.timestamp)));
        uint256[] memory seeds = new uint256[](size);
        for (uint256 i = 0; i < size;) {
            uint256 seed = baseSeed + i;
            seeds[i] = seed;
            seedOf[tokenIds[i]] = seed;
            unchecked {
                ++i;
            }
        }

        uint256 promptLength = bytes(basePrompt).length;
        uint64 aiOracleGasLimit = OracleGasEstimator.getAIOracleCallbackGasLimit(size, promptLength);
        uint256 aiOracleFee = _estimateAIOracleFee(size, aiOracleGasLimit);

        if (!_hasEnoughBalance(delegateCaller, aiOracleFee)) {
            emit NotRequestAIOracle(requestId, delegateCaller);
            return;
        }

        bytes memory batchPrompt = _buildBatchPrompt(baseSeed, baseSeed + size - 1);
        bytes memory _callbackData = abi.encode(requestId);
        uint256 aiOracleRequestId =
            _requestAIOracle(delegateCaller, aiOracleFee, size, batchPrompt, aiOracleGasLimit, _callbackData);

        for (uint256 i = 0; i < size;) {
            tokenIdToAiOracleRequestId[tokenIds[i]] = aiOracleRequestId;
            unchecked {
                ++i;
            }
        }

        emit CallAIOracle(requestId, aiOracleRequestId, delegateCaller);
    }

    /**
     * @notice Callback for AIOracle responses
     * @param output Generated content
     * @param callbackData Original request data
     */
    function aiOracleCallback(
        uint256, /*aiOracleRequestId*/
        bytes calldata output,
        bytes calldata callbackData
    ) external override onlyAIOracleCallback {
        bytes32 requestId = abi.decode(callbackData, (bytes32));
        uint256[] memory tokenIds = requestIdToTokenIds[requestId];
        uint256 size = tokenIds.length;
        if (size == 0) revert InvalidRequestId();

        bytes[] memory cids = _decodeOutput(output);
        if (size != cids.length) revert WrongAIOracleCallback();

        string memory _basePrompt = basePrompt;
        for (uint256 i = 0; i < size;) {
            uint256 tokenId = tokenIds[i];
            bytes memory prompt = _buildPrompt(_basePrompt, seedOf[tokenId]);
            if (_aigcDataOf[tokenId].isEmpty()) {
                this.addAigcData(tokenId, prompt, cids[i], bytes(""));
            } else {
                this.update(prompt, cids[i]);
            }
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Retries AI oracle request
     * @param requestId Original request ID
     */
    function retryRequestAIOracle(bytes32 requestId, address delegateCaller) external payable {
        uint256[] memory tokenIds = requestIdToTokenIds[requestId];
        uint256 size = tokenIds.length;
        if (size == 0) revert InvalidRequestId();
        if (tokenIdToAiOracleRequestId[tokenIds[0]] != 0) revert RequestAlreadyProcessed();

        uint256 promptLength = bytes(basePrompt).length;
        uint64 aiOracleGasLimit = OracleGasEstimator.getAIOracleCallbackGasLimit(size, promptLength);
        uint256 aiOracleFee = _estimateAIOracleFee(size, aiOracleGasLimit);

        if (!_hasEnoughBalance(delegateCaller, aiOracleFee)) {
            revert InsufficientBalance();
        }

        uint256 baseSeed = seedOf[tokenIds[0]];
        uint256 lastTokenSeed = seedOf[tokenIds[size - 1]];
        if (lastTokenSeed != baseSeed + size - 1) revert InvalidSeedRange();

        bytes memory batchPrompt = _buildBatchPrompt(baseSeed, lastTokenSeed);
        bytes memory callbackData = abi.encode(requestId);
        uint256 aiOracleRequestId =
            _requestAIOracle(delegateCaller, aiOracleFee, size, batchPrompt, aiOracleGasLimit, callbackData);

        for (uint256 i = 0; i < size;) {
            tokenIdToAiOracleRequestId[tokenIds[i]] = aiOracleRequestId;
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Returns token URI with metadata
     * @param tokenId Token ID
     * @return string Token URI
     */
    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        if (tokenId >= totalSupply) revert InvalidTokenId();

        string memory imageUrl = _aigcDataOf[tokenId].isEmpty()
            ? DEFAULT_IMAGE_URL
            : string.concat("ipfs://", string(_aigcDataOf[tokenId].get()));

        string memory mediaData = NFTMetadataRenderer.tokenMediaData(imageUrl, "");
        string memory aigcInfo = NFTMetadataRenderer.tokenAIGCInfo(
            basePrompt,
            seedOf[tokenId],
            AIGC_TYPE,
            string(_aigcDataOf[tokenId].get()),
            PROOF_TYPE,
            Strings.toHexString(address(aiOracle)),
            Strings.toString(modelId)
        );

        return NFTMetadataRenderer.createMetadata(name(), description, mediaData, aigcInfo);
    }

    function aigcDataOf(
        uint256 tokenId
    ) external view returns (bytes memory) {
        return _aigcDataOf[tokenId].get();
    }

    /**
     * @notice Returns collection metadata
     * @return string Collection URI
     */
    function contractURI() external view returns (string memory) {
        return NFTMetadataRenderer.encodeContractURIJSON(name(), description);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC721RoyaltyUpgradeable, IERC165) returns (bool) {
        return super.supportsInterface(interfaceId) || interfaceId == type(IERC7007).interfaceId
            || interfaceId == type(IERC7007Updatable).interfaceId || interfaceId == type(IERC7572).interfaceId;
    }

    /**
     * @notice Internal function to get token owner
     * @param tokenId Token ID
     * @return address Owner address
     */
    function _ownerOf(
        uint256 tokenId
    ) internal view override returns (address) {
        if (tokenId >= totalSupply) revert InvalidTokenId();
        return _firstOwnershipChange.get(tokenId) ? super._ownerOf(tokenId) : defaultNFTOwner;
    }

    /**
     * @notice Internal function to update ownership
     * @param to New owner
     * @param tokenId Token ID
     * @param auth Authorized address
     * @return address Previous owner
     */
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = super._update(to, tokenId, auth);
        if (!_firstOwnershipChange.get(tokenId)) {
            _firstOwnershipChange.set(tokenId);
        }
        return from;
    }

    // Internal utility functions
    function _estimateAIOracleFee(uint256 num, uint64 gasLimit) internal view returns (uint256) {
        return aiOracle.estimateFeeBatch(modelId, gasLimit, num);
    }

    function _estimateRandOracleFee(
        uint64 gasLimit
    ) internal view returns (uint256) {
        return randOracle.estimateFee(RAND_ORACLE_MODEL_ID, gasLimit);
    }

    function _requestRandOracle(
        address delegateCaller,
        uint256 fee,
        bytes memory requestEntropy,
        address callbackAddr,
        uint64 gasLimit,
        bytes memory callbackData
    ) internal returns (uint256) {
        if (delegateCaller == address(0)) {
            return
                randOracle.async{value: fee}(RAND_ORACLE_MODEL_ID, requestEntropy, callbackAddr, gasLimit, callbackData);
        }

        payable(delegateCaller).sendValue(msg.value);
        return IORAOracleDelegateCaller(delegateCaller).requestRandOracle(
            RAND_ORACLE_MODEL_ID, requestEntropy, callbackAddr, gasLimit, callbackData
        );
    }

    function _requestAIOracle(
        address delegateCaller,
        uint256 fee,
        uint256 size,
        bytes memory batchPrompt,
        uint64 gasLimit,
        bytes memory callbackData
    ) internal returns (uint256) {
        if (delegateCaller == address(0)) {
            return aiOracle.requestBatchInference{value: fee}(
                size,
                modelId,
                batchPrompt,
                address(this),
                gasLimit,
                callbackData,
                IAIOracle.DA.Calldata,
                IAIOracle.DA.Calldata
            );
        }
        return IORAOracleDelegateCaller(delegateCaller).requestAIOracleBatchInference(
            size,
            modelId,
            batchPrompt,
            address(this),
            gasLimit,
            callbackData,
            IAIOracle.DA.Calldata,
            IAIOracle.DA.Calldata
        );
    }

    function _buildBatchPrompt(uint256 seedStart, uint256 seedEnd) internal view returns (bytes memory) {
        bytes memory seedPart;
        if (seedStart == seedEnd) {
            seedPart = abi.encodePacked('"seed":', Strings.toString(seedStart));
        } else {
            seedPart =
                abi.encodePacked('"seed_range":[', Strings.toString(seedStart), ",", Strings.toString(seedEnd), "]");
        }

        return abi.encodePacked('[{"prompt":"', basePrompt, '",', seedPart, "}]");
    }

    function _buildPrompt(string memory prompt, uint256 seed) internal pure returns (bytes memory) {
        return abi.encodePacked('{"prompt":"', prompt, '","seed":', Strings.toString(seed), "}");
    }

    function _decodeOutput(
        bytes calldata data
    ) internal pure returns (bytes[] memory) {
        if (data.length < 4) revert InvalidDataLength();

        uint32 count = uint32(bytes4(data[:4]));
        bytes[] memory cids = new bytes[](count);
        uint256 offset = 4;

        for (uint32 i = 0; i < count;) {
            if (data.length < offset + 4) revert InvalidDataLength();
            uint32 cidLength = uint32(bytes4(data[offset:offset + 4]));
            offset += 4;

            if (data.length < offset + cidLength) revert InvalidCIDLength();

            bytes memory cidBytes = new bytes(cidLength);
            assembly {
                calldatacopy(add(cidBytes, 32), add(data.offset, offset), cidLength)
            }
            cids[i] = cidBytes;
            offset += cidLength;
            unchecked {
                ++i;
            }
        }
        return cids;
    }

    function _hasEnoughBalance(address delegateCaller, uint256 aiOracleFee) internal view returns (bool) {
        if (delegateCaller == address(0)) {
            return address(this).balance >= aiOracleFee;
        }
        return delegateCaller.balance >= aiOracleFee;
    }

    /* Royalty functions */
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }
}
