// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC2309} from "@openzeppelin/contracts/interfaces/IERC2309.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {ERC721RoyaltyUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721RoyaltyUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {LibBytes} from "../libraries/LibBytes.sol";
import {IAIOracle} from "../interfaces/IAIOracle.sol";
import {IRandOracle} from "../interfaces/IRandOracle.sol";
import {AIOracleCallbackReceiver} from "../libraries/AIOracleCallbackReceiver.sol";
import {RandOracleCallbackReceiver} from "../libraries/RandOracleCallbackReceiver.sol";
import {IORAERC7007} from "../interfaces/IORAERC7007.sol";
import {IERC7572} from "../interfaces/IERC7572.sol";
import {NFTMetadataRenderer} from "../utils/NFTMetadataRenderer.sol";

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
    using BitMaps for BitMaps.BitMap;
    using LibBytes for LibBytes.BytesStorage;

    uint256 public constant RAND_ORACLE_MODEL_ID = 0;
    string public constant DEFAULT_IMAGE_URL = "ipfs://xxx"; // todo: 需要给出默认的图片
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

    /// @notice prompt => tokenId
    mapping(bytes prompt => uint256) public promptToTokenId;

    /// @notice tokenId => seed
    mapping(uint256 tokenId => uint256) public seedOf;

    /// @notice tokenId => aigcData
    mapping(uint256 tokenId => LibBytes.BytesStorage) public aigcDataOf;

    /// @notice requestId => tokenIds[]
    mapping(bytes32 requestId => uint256[]) public requestIdToTokenIds;

    /// @notice tokenId => aiOracleRequestId
    mapping(uint256 tokenId => uint256) public tokenIdToAiOracleRequestId;

    event NewRevealRequest(bytes32 indexed requestId, uint256 randOracleRequestId);
    event CallAIOracle(bytes32 indexed requestId, uint256 aiOracleRequestId);
    event NotRequestAIOracle(bytes32 indexed requestId);

    error UnauthorizedCaller();
    error InsufficientRevealFee();
    error ZeroAddress();
    error AlreadyActivated();
    error InvalidRequestId();
    error InvalidTokenId();
    error EmptyArray();
    error InsufficientBalance();
    error RequestAlreadyProcessed();
    error GaslimitOverflow();

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

    /// @notice Initializes the NFT collection with basic metadata and settings
    /// @param _owner Owner address of the collection
    /// @param prompt Base prompt for AI generation
    /// @param metadataInitializer Encoded metadata (name, symbol, description, nsfw)
    /// @param _modelId AI model identifier
    function initialize(
        address _owner,
        string calldata prompt,
        bytes calldata metadataInitializer,
        uint256 _modelId
    ) public initializer {
        __ERC721Royalty_init();
        __Ownable_init(_owner);
        _initializeMetadata(metadataInitializer);

        basePrompt = prompt;
        modelId = _modelId;
    }

    /// @notice Activates the collection with initial supply and ownership settings
    /// @param _totalSupply Total number of NFTs in collection
    /// @param _defaultNFTOwner Initial owner of all NFTs
    /// @param _operator Address authorized to reveal NFTs
    function activate(uint256 _totalSupply, address _defaultNFTOwner, address _operator) external {
        require(_totalSupply > 0, "Invalid totalSupply");
        if (_defaultNFTOwner == address(0)) revert ZeroAddress();
        if (_operator == address(0)) revert ZeroAddress();
        if (totalSupply != 0) revert AlreadyActivated();

        totalSupply = _totalSupply;
        operator = _operator;
        defaultNFTOwner = _defaultNFTOwner;

        _increaseBalance(_defaultNFTOwner, uint128(_totalSupply));
        emit ConsecutiveTransfer(0, _totalSupply - 1, address(0), _defaultNFTOwner);
    }

    /// @notice Initiates the reveal process for specified NFTs using random seeds
    /// @param tokenIds Array of token IDs to reveal
    /// @dev Caller must ensure tokenIds array contains no duplicates and each tokenId has not been revealed before
    function reveal(
        uint256[] memory tokenIds
    ) external payable {
        if (msg.sender != operator) revert UnauthorizedCaller();
        uint256 size = tokenIds.length;
        if (size == 0) revert EmptyArray();

        bytes32 requestId = keccak256(abi.encodePacked(tokenIds));

        uint64 randOracleGasLimit = _getRandOracleCallbackGasLimit(size);
        uint64 aiOracleGasLimit = _getAIOracleCallbackGasLimit(size);
        uint256 randOracleFee = _estimateRandOracleFee(randOracleGasLimit);
        uint256 aiOracleFee = _estimateAIOracleFee(size, aiOracleGasLimit);
        if (msg.value < randOracleFee + aiOracleFee) revert InsufficientRevealFee();

        uint256 randOracleRequestId = randOracle.async{value: randOracleFee}(
            RAND_ORACLE_MODEL_ID, abi.encodePacked(requestId), address(this), randOracleGasLimit, abi.encode(requestId)
        );
        requestIdToTokenIds[requestId] = tokenIds;
        emit NewRevealRequest(requestId, randOracleRequestId);
    }

    /// @notice Estimates total fee required for revealing NFTs
    /// @param num Number of NFTs to reveal
    /// @return Total fee in wei
    function estimateRevealFee(
        uint256 num
    ) external view returns (uint256) {
        uint64 randOracleGasLimit = _getRandOracleCallbackGasLimit(num);
        uint64 aiOracleGasLimit = _getAIOracleCallbackGasLimit(num);
        return _estimateAIOracleFee(num, aiOracleGasLimit) + _estimateRandOracleFee(randOracleGasLimit);
    }

    /// @notice Adds AI-generated content data to a token
    /// @param tokenId Token ID to update
    /// @param prompt Generation prompt used
    /// @param aigcData Generated content data
    /// @param proof Verification proof
    function addAigcData(
        uint256 tokenId,
        bytes memory prompt,
        bytes memory aigcData,
        bytes memory proof
    ) external onlySelf {
        require(aigcDataOf[tokenId].isEmpty(), "AigcData exists");

        promptToTokenId[prompt] = tokenId;
        aigcDataOf[tokenId].set(aigcData);
        emit AigcData(tokenId, prompt, aigcData, proof);
        emit MetadataUpdate(tokenId);
    }

    /// @notice Verifies AI-generated content authenticity
    /// @param prompt Original generation prompt
    /// @param aigcData Generated content data
    /// @param proof Verification proof
    function verify(
        bytes calldata prompt,
        bytes calldata aigcData,
        bytes calldata /* proof */
    ) external view override returns (bool success) {
        uint256 tokenId = promptToTokenId[prompt];
        uint256 aiOracleRequestId = tokenIdToAiOracleRequestId[tokenId];
        bytes memory currentAigcData = aigcDataOf[tokenId].get();
        return aiOracle.isFinalized(aiOracleRequestId) && keccak256(aigcData) == keccak256(currentAigcData);
    }

    /// @notice Updates AI-generated content for a token
    /// @param prompt Generation prompt
    /// @param aigcData New generated content data
    function update(bytes memory prompt, bytes memory aigcData) external onlySelf {
        uint256 tokenId = promptToTokenId[prompt];
        aigcDataOf[tokenId].set(aigcData);

        emit Update(tokenId, prompt, aigcData);
        emit MetadataUpdate(tokenId);
    }

    /// @notice Callback handler for randOracle responses
    /// @param output Random value output
    /// @param callbackData Original request data
    function awaitRandOracle(
        uint256, /* randOracleRequestId */
        uint256 output,
        bytes calldata callbackData
    ) external override onlyRandOracleCallback {
        bytes32 requestId = abi.decode(callbackData, (bytes32));
        uint256[] memory tokenIds = requestIdToTokenIds[requestId];
        uint256 size = tokenIds.length;
        if (size == 0) revert InvalidRequestId();

        uint256[] memory seeds = new uint256[](size);
        for (uint256 i = 0; i < size; i++) {
            uint256 seed = output ^ uint256(keccak256(abi.encodePacked(tokenIds[i])));
            seeds[i] = seed;
            seedOf[tokenIds[i]] = seed;
        }
        uint64 aiOracleGasLimit = _getAIOracleCallbackGasLimit(size);
        uint256 aiOracleFee = _estimateAIOracleFee(size, aiOracleGasLimit);

        if (address(this).balance < aiOracleFee) {
            // todo: 考虑写入tokenIdToAiOracleRequestId,将slot的value变为非0
            emit NotRequestAIOracle(requestId);
            return;
        }

        bytes memory batchPrompt = _buildBatchPrompt(seeds);
        uint256 aiOracleRequestId = _requestAIOracle(size, batchPrompt, aiOracleFee, aiOracleGasLimit, callbackData);
        for (uint256 i; i < size; i++) {
            tokenIdToAiOracleRequestId[tokenIds[i]] = aiOracleRequestId;
        }
    }

    /// @notice Callback handler for AIOracle responses
    /// @param output Generated content data
    /// @param callbackData Original request data
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
        require(size == cids.length, "Wrong output");

        string memory _basePrompt = basePrompt;

        for (uint256 i = 0; i < size; i++) {
            uint256 tokenId = tokenIds[i];
            bytes memory prompt = _buildPrompt(_basePrompt, seedOf[tokenId]);
            if (aigcDataOf[tokenId].isEmpty()) {
                this.addAigcData(tokenId, prompt, cids[i], bytes(""));
            } else {
                this.update(prompt, cids[i]);
            }
        }
    }

    /// @notice Retries AI oracle request for failed reveals
    /// @param requestId Original request ID to retry
    function retryRequestAIOracle(
        bytes32 requestId
    ) external payable {
        uint256[] memory tokenIds = requestIdToTokenIds[requestId];
        uint256 size = tokenIds.length;
        if (size == 0) revert InvalidRequestId();
        if (tokenIdToAiOracleRequestId[tokenIds[0]] != 0) revert RequestAlreadyProcessed();

        uint64 aiOracleGasLimit = _getAIOracleCallbackGasLimit(size);
        uint256 aiOracleFee = _estimateAIOracleFee(size, aiOracleGasLimit);

        if (address(this).balance < aiOracleFee) {
            revert InsufficientBalance();
        }

        uint256[] memory seeds = new uint256[](size);
        for (uint256 i; i < size; i++) {
            seeds[i] = seedOf[tokenIds[i]];
        }
        bytes memory batchPrompt = _buildBatchPrompt(seeds);
        bytes memory callbackData = abi.encode(requestId);
        uint256 aiOracleRequestId = _requestAIOracle(size, batchPrompt, aiOracleFee, aiOracleGasLimit, callbackData);

        for (uint256 i; i < size; i++) {
            tokenIdToAiOracleRequestId[tokenIds[i]] = aiOracleRequestId;
        }
    }

    /// @notice Returns token URI with metadata and AI-generated content
    /// @param tokenId Token ID to query
    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        if (tokenId >= totalSupply) revert InvalidTokenId();

        string memory imageUrl;
        if (aigcDataOf[tokenId].isEmpty()) {
            imageUrl = DEFAULT_IMAGE_URL;
        } else {
            imageUrl = string.concat("ipfs://", string(aigcDataOf[tokenId].get()));
        }
        string memory mediaData = NFTMetadataRenderer.tokenMediaData(imageUrl, "");
        string memory aigcInfo = NFTMetadataRenderer.tokenAIGCInfo(
            basePrompt,
            AIGC_TYPE,
            string(aigcDataOf[tokenId].get()),
            PROOF_TYPE,
            Strings.toHexString(address(aiOracle)),
            Strings.toString(modelId)
        );
        return NFTMetadataRenderer.createMetadata(name(), description, mediaData, aigcInfo);
    }

    /// @notice Returns collection-level metadata
    function contractURI() external view returns (string memory) {
        return NFTMetadataRenderer.encodeContractURIJSON(name(), description);
    }

    /// @notice Internal function to get token owner
    /// @param tokenId Token ID to query
    function _ownerOf(
        uint256 tokenId
    ) internal view override returns (address) {
        if (tokenId >= totalSupply) revert InvalidTokenId();
        return _firstOwnershipChange.get(tokenId) ? super._ownerOf(tokenId) : defaultNFTOwner;
    }

    /// @notice Internal function to update token ownership
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = super._update(to, tokenId, auth);
        if (_firstOwnershipChange.get(tokenId) == false) {
            _firstOwnershipChange.set(tokenId);
        }
        return from;
    }

    // Internal utility functions...
    function _getAIOracleCallbackGasLimit(
        uint256 num
    ) internal view returns (uint64) {
        uint256 promptLength = bytes(basePrompt).length;
        uint256 numTimesPromptLen = num * promptLength;
        uint256 baseGas = num * 105_205 + numTimesPromptLen + promptLength / 32 * 2100 + 14_300;
        uint256 wordSize = (num * 191 * 32 + numTimesPromptLen * 6) / 32;
        uint256 memoryGas = (wordSize * wordSize) / 512 + wordSize * 3;
        uint256 totalGas = baseGas + memoryGas;
        if (totalGas > type(uint64).max) revert GaslimitOverflow();
        return uint64(totalGas);
    }

    function _getRandOracleCallbackGasLimit(
        uint256 num
    ) internal view returns (uint64) {
        uint256 promptLength = bytes(basePrompt).length;
        uint256 batchPromptLength = num * (99 + promptLength) + 4;
        uint256 slotNum = (batchPromptLength + 31) / 32;
        uint256 baseGas = slotNum * 23_764 + num * 32_100 + 353_700;
        uint256 wordSize = slotNum * 26 + num * (32 * 200 + promptLength * 23) / 32;
        uint256 memoryGas = (wordSize * wordSize) / 512 + wordSize * 3;
        uint256 totalGas = baseGas + memoryGas;
        if (totalGas > type(uint64).max) revert GaslimitOverflow();
        return uint64(totalGas);
    }

    function _estimateAIOracleFee(uint256 num, uint64 gasLimit) internal view returns (uint256) {
        return aiOracle.estimateFeeBatch(modelId, gasLimit, num);
    }

    function _estimateRandOracleFee(
        uint64 gasLimit
    ) internal view returns (uint256) {
        return randOracle.estimateFee(RAND_ORACLE_MODEL_ID, "", address(this), gasLimit, "");
    }

    function _requestAIOracle(
        uint256 size,
        bytes memory batchPrompt,
        uint256 fee,
        uint64 gasLimit,
        bytes memory callbackData
    ) internal returns (uint256) {
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

    function _buildBatchPrompt(
        uint256[] memory seeds
    ) internal view returns (bytes memory) {
        string memory _basePrompt = basePrompt;
        bytes memory batchPrompt = "[";
        for (uint256 i = 0; i < seeds.length; i++) {
            if (i > 0) {
                batchPrompt = bytes.concat(batchPrompt, ",");
            }
            bytes memory prompt = _buildPrompt(_basePrompt, seeds[i]);
            batchPrompt = bytes.concat(batchPrompt, prompt);
        }
        return bytes.concat(batchPrompt, "]");
    }

    function _buildPrompt(string memory prompt, uint256 seed) internal pure returns (bytes memory) {
        return abi.encodePacked('{"prompt":"', prompt, '","seed":', Strings.toString(seed), "}");
    }

    function _decodeOutput(
        bytes calldata data
    ) internal pure returns (bytes[] memory) {
        require(data.length >= 4, "Data too short");
        uint32 count = uint32(bytes4(data[:4]));
        bytes[] memory cids = new bytes[](count);
        uint256 offset = 4;
        for (uint32 i = 0; i < count; i++) {
            require(data.length >= offset + 4, "Invalid data length");
            uint32 cidLength = uint32(bytes4(data[offset:offset + 4]));
            offset += 4;
            require(data.length >= offset + cidLength, "Invalid CID length");

            bytes memory cidBytes = new bytes(cidLength);
            assembly {
                calldatacopy(add(cidBytes, 32), add(data.offset, offset), cidLength)
            }
            cids[i] = cidBytes;
            offset += cidLength;
        }
        return cids;
    }

    /* royalty */
    /// @notice Sets default royalty for all tokens
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) public onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    /// @notice Sets royalty for a specific token
    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) public onlyOwner {
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }
}
