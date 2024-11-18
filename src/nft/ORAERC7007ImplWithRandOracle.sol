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
// import {ORAUtils} from "../utils/ORAUtils.sol";

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
    // 允许调用reveal接口的address
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

    /// @notice tokenId => requestId
    mapping(uint256 tokenId => bytes32) public tokenIdToRequestId;

    /// @notice requestId => tokenIds[]
    mapping(bytes32 requestId => uint256[]) public requestIdToTokenIds;

    /// @notice tokenId => aiOracleRequestId
    mapping(uint256 tokenId => uint256) public tokenIdToAiOracleRequestId;

    event NewRevealRequest(bytes32 indexed requestId, uint256 randOracleRequestId);
    event NotRequestAIOracle(bytes32 indexed requestId);

    error InsufficientRevealFee();
    error ZeroAddress();
    error InvalidRequestId();

    modifier onlySelf() {
        require(msg.sender == address(this), "Only self can call");
        _;
    }

    constructor(
        IAIOracle _aiOracle,
        IRandOracle _randOracle
    ) AIOracleCallbackReceiver(_aiOracle) RandOracleCallbackReceiver(_randOracle) {
        _disableInitializers();
    }

    struct CollectionMetadata {
        string name;
        string symbol;
        string description;
        string prompt;
        bool nsfw;
    }

    function initialize(CollectionMetadata calldata metadata, address _owner, uint256 _modelId) public initializer {
        __ERC721_init(metadata.name, metadata.symbol);
        __ERC721Royalty_init();
        __Ownable_init(_owner);
        modelId = _modelId;
        basePrompt = metadata.prompt;
        nsfw = metadata.nsfw;
        description = metadata.description;
    }

    function activate(uint256 _totalSupply, address _defaultNFTOwner, address _operator) external {
        require(_totalSupply > 0);
        if (_defaultNFTOwner == address(0)) revert ZeroAddress();
        if (_operator == address(0)) revert ZeroAddress();

        require(totalSupply == 0, "Already activated");

        totalSupply = _totalSupply;
        operator = _operator;

        _increaseBalance(_defaultNFTOwner, uint128(_totalSupply));
        emit ConsecutiveTransfer(0, _totalSupply - 1, address(0), _defaultNFTOwner);
    }

    function reveal(
        uint256[] memory tokenIds
    ) external payable {
        require(msg.sender == operator, "Only operator");
        uint256 size = tokenIds.length;
        require(size > 0, "TokenIds can not be empty");

        bytes32 requestId = keccak256(abi.encodePacked(tokenIds));
        // todo: randOracle.contributeEntropy(bytes32) 考虑是否加这个
        uint64 randOracleGasLimit = _getRandOracleCallbackGasLimit(size);
        uint64 aiOracleGasLimit = _getAIOracleCallbackGasLimit(size);
        uint256 randOracleFee = _estimateRandOracleFee(randOracleGasLimit);
        uint256 aiOracleFee = _estimateAIOracleFee(size, aiOracleGasLimit);
        if (msg.value < randOracleFee + randOracleFee) revert InsufficientRevealFee();

        uint256 randOracleRequestId = randOracle.async{value: randOracleFee}(
            RAND_ORACLE_MODEL_ID,
            abi.encodePacked(requestId), // requestEntropy
            address(this),
            randOracleGasLimit,
            abi.encode(requestId)
        );
        requestIdToTokenIds[requestId] = tokenIds;
        emit NewRevealRequest(requestId, randOracleRequestId);
    }

    function estimateRevealFee(
        uint256 num
    ) public view returns (uint256) {
        uint64 randOracleGasLimit = _getRandOracleCallbackGasLimit(num);
        uint64 aiOracleGasLimit = _getAIOracleCallbackGasLimit(num);
        return _estimateAIOracleFee(num, aiOracleGasLimit) + _estimateRandOracleFee(randOracleGasLimit);
    }

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

    function update(bytes memory prompt, bytes memory aigcData) external onlySelf {
        uint256 tokenId = promptToTokenId[prompt];
        aigcDataOf[tokenId].set(aigcData);

        emit Update(tokenId, prompt, aigcData);
        emit MetadataUpdate(tokenId);
    }

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
            emit NotRequestAIOracle(requestId);
            return;
        }
        bytes memory batchPrompt = _buildBatchPrompt(seeds);

        _requestAIOracle(size, batchPrompt, aiOracleFee, aiOracleGasLimit, callbackData);
    }

    function _requestAIOracle(
        uint256 size,
        bytes memory batchPrompt,
        uint256 fee,
        uint64 gasLimit,
        bytes calldata callbackData
    ) internal returns (uint256 aiOracleRequestId) {
        aiOracleRequestId = aiOracle.requestBatchInference{value: fee}(
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
    ) internal view returns (bytes memory batchPrompt) {
        string memory _basePrompt = basePrompt;
        batchPrompt = "[";
        for (uint256 i = 0; i < seeds.length; i++) {
            if (i > 0) {
                batchPrompt = bytes.concat(batchPrompt, ",");
            }
            bytes memory prompt = _buildPrompt(_basePrompt, seeds[i]);
            batchPrompt = bytes.concat(batchPrompt, prompt);
        }
        batchPrompt = bytes.concat(batchPrompt, "]");
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

    function aiOracleCallback(
        uint256 aiOracleRequestId,
        bytes calldata output,
        bytes calldata callbackData
    ) external override onlyAIOracleCallback {
        bytes32 requestId = abi.decode(callbackData, (bytes32));
        uint256[] memory tokenIds = requestIdToTokenIds[requestId];
        uint256 size = tokenIds.length;
        require(size != 0, "wrong requestId");

        bytes[] memory cids = _decodeOutput(output);
        require(size == cids.length, "length mismatch");

        string memory _basePrompt = basePrompt;

        for (uint256 i = 0; i < size; i++) {
            uint256 tokenId = tokenIds[i];
            tokenIdToAiOracleRequestId[tokenIds[i]] = aiOracleRequestId;
            bytes memory prompt = _buildPrompt(_basePrompt, seedOf[tokenId]);
            if (aigcDataOf[tokenId].isEmpty()) {
                this.addAigcData(tokenId, prompt, cids[i], bytes(""));
            } else {
                this.update(prompt, cids[i]);
            }
        }
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
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

    function contractURI() external view returns (string memory) {
        return NFTMetadataRenderer.encodeContractURIJSON(name(), description);
    }

    function _ownerOf(
        uint256 tokenId
    ) internal view override returns (address) {
        if (_firstOwnershipChange.get(tokenId) == false) {
            return defaultNFTOwner;
        }
        return super._ownerOf(tokenId);
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        address from = super._update(to, tokenId, auth);
        if (_firstOwnershipChange.get(tokenId) == false) {
            _firstOwnershipChange.set(tokenId);
        }
        return from;
    }

    function _getAIOracleCallbackGasLimit(
        uint256 num
    ) internal view returns (uint64) {
        uint256 promptLength = bytes(basePrompt).length;
        uint256 numTimesPromptLen = num * promptLength;
        uint256 baseGas = num * 105_205 + numTimesPromptLen + promptLength / 32 * 2100 + 14_300;
        uint256 wordSize = (num * 191 * 32 + numTimesPromptLen * 6) / 32;
        uint256 memoryGas = (wordSize * wordSize) / 512 + wordSize * 3;
        uint256 totalGas = baseGas + memoryGas;
        require(totalGas <= type(uint64).max, "Gas limit overflow");
        return uint64(totalGas);
    }

    function _getRandOracleCallbackGasLimit(
        uint256 num
    ) internal view returns (uint64) {
        return uint64(7007);
    }

    function _estimateAIOracleFee(uint256 num, uint64 gasLimit) internal view returns (uint256) {
        return aiOracle.estimateFeeBatch(modelId, gasLimit, num);
    }

    function _estimateRandOracleFee(
        uint64 gasLimit
    ) internal view returns (uint256) {
        return randOracle.estimateFee(RAND_ORACLE_MODEL_ID, "", address(this), gasLimit, "");
    }

    /* royalty */
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) public onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) public onlyOwner {
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }
}
