// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC2309} from "@openzeppelin/contracts/interfaces/IERC2309.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {ERC721RoyaltyUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721RoyaltyUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {AIOracleCallbackReceiver} from "../libraries/AIOracleCallbackReceiver.sol";
import {IAIOracle} from "../interfaces/IAIOracle.sol";
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
    AIOracleCallbackReceiver
{
    using BitMaps for BitMaps.BitMap;

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
    uint64 public constant addAigcDataGasLimit = 50_000; // todo: 测量

    // prompt => tokenId
    mapping(bytes prompt => uint256) promptToTokenId;
    // tokenId => seed
    mapping(uint256 tokenId => uint256) public seedOf;
    // tokenId => aigcData
    mapping(uint256 tokenId => bytes) public aigcDataOf;
    // tokenId => ora requestId
    mapping(uint256 tokenId => uint256) tokenIdToRequestId;
    // ora requestId => tokenIds
    mapping(uint256 requestId => uint256[]) requests;

    constructor(
        IAIOracle _aiOracle
    ) AIOracleCallbackReceiver(_aiOracle) {
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
        require(_defaultNFTOwner != address(0));
        require(_operator != address(0));
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

    // opML情况下，只检查数据是否finalized和aigcData是否最新的
    function verify(
        bytes calldata prompt,
        bytes calldata aigcData,
        bytes calldata /* proof */
    ) external view override returns (bool success) {
        uint256 tokenId = promptToTokenId[prompt];
        uint256 requestId = tokenIdToRequestId[tokenId];

        bytes storage currentAigcData = aigcDataOf[tokenId];
        return aiOracle.isFinalized(requestId) && keccak256(aigcData) == keccak256(currentAigcData);
    }

    function update(bytes memory prompt, bytes memory aigcData) public {
        require(msg.sender == address(this));

        uint256 tokenId = promptToTokenId[prompt];
        aigcDataOf[tokenId] = aigcData;

        emit Update(tokenId, prompt, aigcData);
        emit MetadataUpdate(tokenId);
    }

    function getSeed(
        uint256 tokenId
    ) internal view returns (uint256) {
        // todo: 采用随机的方式生成seed
        return tokenId;
    }
    // pre sale ()
    // NFT price Strategy
    // public mint (after pre sale)

    function reveal(
        uint256[] memory tokenIds
    ) external payable {
        require(msg.sender == operator, "Only operator");

        uint256 size = tokenIds.length;
        require(size > 0);
        bytes[] memory prompts = new bytes[](size);
        uint256[] memory seeds = new uint256[](size);
        bytes memory batchPrompt = "[";
        for (uint256 i = 0; i < size; i++) {
            // uint256 tokenId = tokenIds[i];
            if (i > 0) {
                batchPrompt = bytes.concat(batchPrompt, ",");
            }
            uint256 seed = getSeed(tokenIds[i]);
            bytes memory prompt = ORAUtils.buildPrompt(basePrompt, seed);
            prompts[i] = prompt;
            seeds[i] = seed;
            batchPrompt = bytes.concat(batchPrompt, prompt);
        }
        batchPrompt = bytes.concat(batchPrompt, "]");

        uint64 gasLimit = getGasLimit(tokenIds.length);
        uint256 requestId = aiOracle.requestBatchInference{value: msg.value}(
            size, modelId, bytes(batchPrompt), address(this), gasLimit, "", IAIOracle.DA.Calldata, IAIOracle.DA.Calldata
        );

        for (uint256 i = 0; i < size; i++) {
            uint256 tokenId = tokenIds[i];
            seedOf[tokenId] = seeds[i];
            tokenIdToRequestId[tokenId] = requestId;
        }

        requests[requestId] = tokenIds;
    }

    function getGasLimit(
        uint256 num
    ) internal pure returns (uint64) {
        // todo: 需要结合优化时,
        return uint64(17_737 + (14_766 + 29_756) * num);
    }

    // 估算调用aiOracle需要的费用
    function estimateFee(
        uint256 num
    ) public view returns (uint256) {
        return aiOracle.estimateFeeBatch(modelId, getGasLimit(num), num);
    }

    // 注意此函数在opML下可能会被多次调用
    function aiOracleCallback(
        uint256 requestId,
        bytes calldata output,
        bytes calldata /* callbackData */
    ) external override onlyAIOracleCallback {
        uint256[] storage tokenIds = requests[requestId];
        require(tokenIds.length > 0);

        bytes[] memory cids = ORAUtils.decodeCIDs(output); // 50个时 gas: 65613
        require(tokenIds.length == cids.length);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            bytes memory prompt = ORAUtils.buildPrompt(basePrompt, seedOf[tokenId]);
            if (aigcDataOf[tokenId].length == 0) {
                addAigcData(tokenId, prompt, cids[i], bytes(""));
            } else {
                update(prompt, cids[i]); // update时的gas小于addAigcData的
            }
        }
    }

    /* royalty */
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) public onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) public onlyOwner {
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }
}
