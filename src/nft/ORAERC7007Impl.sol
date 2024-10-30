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
import {IERC7007Updatable} from "../interfaces/IERC7007Updatable.sol";
import {ITotalSupply} from "../interfaces/ITotalSupply.sol";
import {NFTMetadataRenderer} from "../utils/NFTMetadataRenderer.sol";
import {ORAUtils} from "../utils/ORAUtils.sol";

// todo: 使用openzeppelin的ERC721部分优化，等完善测试后进行
contract ORAERC7007Impl is
    ERC721RoyaltyUpgradeable,
    IERC4906,
    IERC2309,
    IERC7007Updatable,
    ITotalSupply,
    OwnableUpgradeable,
    AIOracleCallbackReceiver
{
    using BitMaps for BitMaps.BitMap;

    uint256 public modelId;
    string public basePrompt;
    bool public nsfw;

    uint256 public totalSupply;
    address public aiOracleManager; //用于管理aiOracle调用流程

    address private defaultNFTOwner;
    BitMaps.BitMap private _firstOwnershipChange; //记录某个nft是否完成初次ownership变更

    string public constant defaultImageUrl = "ipfs://xxx"; //todo: 默认图片链接
    string public constant aigcType = "image";
    string public constant proofType = "fraud";
    string public constant description = ""; // todo: 增加描述
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

    // contractURI
    constructor(
        IAIOracle _aiOracle
    ) AIOracleCallbackReceiver(_aiOracle) {
        _disableInitializers();
    }

    function initialize(
        string memory name,
        string memory symbol,
        string memory _basePrompt,
        address _owner,
        bool _nsfw,
        uint256 _modelId
    ) public initializer {
        __ERC721_init(name, symbol);
        __ERC721Royalty_init();
        __Ownable_init(_owner);
        modelId = _modelId;
        aiOracleManager = address(this);
        basePrompt = _basePrompt;
        nsfw = _nsfw;
    }

    function mintAll(address to, uint256 quantity) public onlyOwner {
        require(to != address(0));
        require(quantity > 0);
        require(totalSupply == 0, "Has minted all");
        defaultNFTOwner = to;
        totalSupply = quantity;
        _increaseBalance(to, uint128(totalSupply));
        emit ConsecutiveTransfer(0, totalSupply - 1, address(0), to);
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

    /* 涉及到batchMint相关优化逻辑 */
    // todo: 可以模块化
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

    /* ERC7007  */
    // 调用这个函数来完成数据的绑定
    // 此处修改了一些修饰符，但不影响对interface的兼容
    // 注意此函数只能被调用一次
    function addAigcData(uint256 tokenId, bytes memory prompt, bytes memory aigcData, bytes memory proof) external {
        require(msg.sender == aiOracleManager, "Only aiOracleManager");
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

    function update(bytes calldata prompt, bytes calldata aigcData) external {
        require(msg.sender == aiOracleManager, "Only aiOracleManager");

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

    function reveal(
        uint256[] memory tokenIds
    ) external payable {
        uint256 size = tokenIds.length;
        require(size > 0);
        bytes[] memory prompts = new bytes[](size);
        uint256[] memory seeds = new uint256[](size);
        bytes memory batchPrompt = "[";
        for (uint256 i = 0; i < size; i++) {
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
        // todo: 检查requestId
        uint256[] storage tokenIds = requests[requestId];
        require(tokenIds.length > 0);

        bytes[] memory cids = ORAUtils.decodeCIDs(output);
        require(tokenIds.length == cids.length);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            // bytes storage prompt = promptOf[tokenId];
            uint256 tokenId = tokenIds[i];
            bytes memory prompt = ORAUtils.buildPrompt(basePrompt, seedOf[tokenId]);
            if (aigcDataOf[tokenId].length == 0) {
                this.addAigcData(tokenId, prompt, cids[i], bytes(""));
            } else {
                this.update(prompt, cids[i]);
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
