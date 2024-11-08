// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC2309} from "@openzeppelin/contracts/interfaces/IERC2309.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {ERC721RoyaltyUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721RoyaltyUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {IAIOracle} from "../interfaces/IAIOracle.sol";
import {IRandOracle} from "../interfaces/IRandOracle.sol";
import {AIOracleCallbackReceiver} from "../libraries/AIOracleCallbackReceiver.sol";
import {RandOracleCallbackReceiver} from "../libraries/RandOracleCallbackReceiver.sol";
import {IORAERC7007} from "../interfaces/IORAERC7007.sol";
import {IERC7572} from "../interfaces/IERC7572.sol";
import {NFTMetadataRenderer} from "../utils/NFTMetadataRenderer.sol";
import {ORAUtils} from "../utils/ORAUtils.sol";

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

    uint256 public constant RAND_ORACLE_MODEL_ID = 0;
    uint256 public modelId;
    string public basePrompt;
    bool public nsfw;

    uint256 public totalSupply;
    address public operator;

    address private defaultNFTOwner;
    BitMaps.BitMap private _firstOwnershipChange;

    string public constant defaultImageUrl = "ipfs://xxx";
    string public constant aigcType = "image";
    string public constant proofType = "fraud";
    string public constant description = "";

    struct RevealRequest {
        uint256[] tokenIds; // // todo: 考虑优化方案: tokenid使用uint16 (最大65535), 将tokenid压缩成bytes
        uint256 aiOracleRequestId;
        uint256 randOracleRequestId;
    }

    // prompt => tokenId
    mapping(bytes prompt => uint256) promptToTokenId;
    // tokenId => seed
    mapping(uint256 tokenId => uint256) public seedOf;
    // tokenId => aigcData
    mapping(uint256 tokenId => bytes) public aigcDataOf;
    // 用于opml校验
    // tokenId => requestId
    mapping(uint256 tokenId => bytes32) tokenIdToRequestId;
    // 在aiOracle回调时使用，用于找到对应的tokenIds

    // aiOracle requestId => tokenIds
    mapping(bytes32 requestId => RevealRequest) requests;

    error ZeroAddress();

    constructor(
        IAIOracle _aiOracle,
        IRandOracle _randOracle
    ) AIOracleCallbackReceiver(_aiOracle) RandOracleCallbackReceiver(_randOracle) {
        _disableInitializers();
    }

    function initialize(
        string calldata name,
        string calldata symbol,
        string calldata _basePrompt,
        address _owner,
        bool _nsfw,
        uint256 _modelId
    ) public initializer {
        __ERC721_init(name, symbol);
        __ERC721Royalty_init();
        __Ownable_init(_owner);
        modelId = _modelId;
        basePrompt = _basePrompt;
        nsfw = _nsfw;
    }

    function activate(uint256 _totalSupply, address _defaultNFTOwner, address _operator) external {
        require(_totalSupply > 0);
        if (_defaultNFTOwner == address(0) || _operator == address(0)) revert ZeroAddress();
        require(totalSupply == 0, "Already activated");

        totalSupply = _totalSupply;
        operator = _operator;

        _increaseBalance(_defaultNFTOwner, uint128(_totalSupply));
        emit ConsecutiveTransfer(0, _totalSupply - 1, address(0), _defaultNFTOwner);
    }

    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        string memory imageUrl;
        if (aigcDataOf[tokenId].length > 0) {
            imageUrl = string.concat("ipfs://", string(aigcDataOf[tokenId]));
        } else {
            imageUrl = defaultImageUrl;
        }
        string memory mediaData = NFTMetadataRenderer.tokenMediaData(imageUrl, "");
        string memory aigcInfo = NFTMetadataRenderer.tokenAIGCInfo(
            basePrompt,
            aigcType,
            string(aigcDataOf[tokenId]),
            proofType,
            Strings.toHexString(address(aiOracle)),
            Strings.toString(modelId)
        );
        return NFTMetadataRenderer.createMetadata(
            name(),
            description, //todo: description
            mediaData,
            aigcInfo
        );
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

    function addAigcData(uint256 tokenId, bytes memory prompt, bytes memory aigcData, bytes memory proof) public {
        require(msg.sender == address(this));
        require(aigcDataOf[tokenId].length == 0, "AigcData exists");

        promptToTokenId[prompt] = tokenId;
        aigcDataOf[tokenId] = aigcData;
        emit AigcData(tokenId, prompt, aigcData, proof);

        emit MetadataUpdate(tokenId);
    }

    function verify(
        bytes calldata prompt,
        bytes calldata aigcData,
        bytes calldata /* proof */
    ) external view override returns (bool success) {
        uint256 tokenId = promptToTokenId[prompt];
        bytes32 requestId = tokenIdToRequestId[tokenId];
        RevealRequest storage request = requests[requestId];
        bytes storage currentAigcData = aigcDataOf[tokenId];
        return aiOracle.isFinalized(request.aiOracleRequestId) && keccak256(aigcData) == keccak256(currentAigcData);
    }

    function update(bytes memory prompt, bytes memory aigcData) public {
        require(msg.sender == address(this));

        uint256 tokenId = promptToTokenId[prompt];
        aigcDataOf[tokenId] = aigcData;

        emit Update(tokenId, prompt, aigcData);
        emit MetadataUpdate(tokenId);
    }

    function reveal(
        uint256[] memory tokenIds
    ) external payable {
        require(msg.sender == operator, "Only operator");
        uint256 size = tokenIds.length;
        require(size > 0);

        bytes32 requestId = keccak256(abi.encodePacked(tokenIds));
        RevealRequest storage request = requests[requestId];
        // todo: randOracle.contributeEntropy(bytes32) 考虑是否加这个
        uint64 gasLimit = 7500;
        uint256 fee = _estimateRandOracleFee(gasLimit);
        uint256 aigcFee = _estimateAIOracleFee(size);
        require(msg.value >= fee + aigcFee);
        uint256 randOracleRequestId = randOracle.async{value: fee}(
            RAND_ORACLE_MODEL_ID,
            abi.encode(requestId), // requestEntropy
            address(this),
            gasLimit,
            abi.encode(requestId)
        );
        request.tokenIds = tokenIds;
        request.randOracleRequestId = randOracleRequestId; // todo: 使用emit event
    }

    function getGasLimit(
        uint256 num
    ) internal pure returns (uint64) {
        // todo: 需要结合优化时,
        // todo: 结合length
        return uint64(17_737 + (14_766 + 29_756) * num);
    }

    function estimateRevealFee(
        uint256 num
    ) public view returns (uint256) {
        return _estimateAIOracleFee(num) + _estimateRandOracleFee(uint64(7500));
    }

    function _estimateAIOracleFee(
        uint256 num
    ) internal view returns (uint256) {
        return aiOracle.estimateFeeBatch(modelId, getGasLimit(num), num);
    }

    function _estimateRandOracleFee(
        uint64 gasLimit
    ) internal view returns (uint256) {
        return randOracle.estimateFee(RAND_ORACLE_MODEL_ID, "", address(this), gasLimit, "");
    }

    function aiOracleCallback(
        uint256, /* aiOracleRequestId */
        bytes calldata output,
        bytes calldata callbackData
    ) external override onlyAIOracleCallback {
        bytes32 requestId = abi.decode(callbackData, (bytes32));
        RevealRequest storage request = requests[requestId];
        uint256 size = request.tokenIds.length;
        require(size != 0, "wrong requestId");

        bytes[] memory cids = ORAUtils.decodeCIDs(output);
        require(size == cids.length);

        for (uint256 i = 0; i < size; i++) {
            uint256 tokenId = request.tokenIds[i];
            tokenIdToRequestId[tokenId] = requestId;
            bytes memory prompt = ORAUtils.buildPrompt(basePrompt, seedOf[tokenId]);
            if (aigcDataOf[tokenId].length == 0) {
                addAigcData(tokenId, prompt, cids[i], bytes(""));
            } else {
                update(prompt, cids[i]); // update时的gas小于addAigcData的
            }
        }
    }

    function awaitRandOracle(
        uint256, /* randOracleRequestId */
        uint256 output,
        bytes calldata callbackData
    ) external override onlyRandOracleCallback {
        bytes32 requestId = abi.decode(callbackData, (bytes32));
        RevealRequest storage request = requests[requestId];
        uint256 size = request.tokenIds.length;
        require(size != 0, "wrong requestId");

        bytes memory batchPrompt = "[";

        for (uint256 i = 0; i < size; i++) {
            if (i > 0) {
                batchPrompt = bytes.concat(batchPrompt, ",");
            }
            uint256 seed = output ^ i;
            bytes memory prompt = ORAUtils.buildPrompt(basePrompt, seed);
            seedOf[request.tokenIds[i]] = seed;
            batchPrompt = bytes.concat(batchPrompt, prompt);
        }

        batchPrompt = bytes.concat(batchPrompt, "]");
        uint256 aiOracleRequestId = aiOracle.requestBatchInference{value: _estimateAIOracleFee(size)}(
            size,
            modelId,
            bytes(batchPrompt),
            address(this),
            getGasLimit(size),
            callbackData,
            IAIOracle.DA.Calldata,
            IAIOracle.DA.Calldata
        );
        request.aiOracleRequestId = aiOracleRequestId;
    }

    /* royalty */
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) public onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) public onlyOwner {
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }
}
