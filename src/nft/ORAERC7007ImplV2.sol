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
import {IERC7007Updatable} from "../interfaces/IERC7007Updatable.sol";
import {ITotalSupply} from "../interfaces/ITotalSupply.sol";
import {NFTMetadataRenderer} from "../utils/NFTMetadataRenderer.sol";
import {IAIOracleManager} from "../interfaces/IAIOracleManager.sol";
import {ORAUtils} from "../utils/ORAUtils.sol";

// todo: 使用openzeppelin的ERC721部分优化，等完善测试后进行
contract ORAERC7007ImplV2 is
    ERC721RoyaltyUpgradeable,
    IERC4906,
    IERC2309,
    IERC7007Updatable,
    ITotalSupply,
    OwnableUpgradeable
{
    using BitMaps for BitMaps.BitMap;

    string public constant unRevealImageUrl = "ipfs://xxx"; //todo: 默认图片链接
    string public constant aigcType = "image";
    string public constant proofType = "fraud";
    string public constant description = ""; // todo: 增加描述
    uint64 public constant addAigcDataGasLimit = 50_000; // todo: 测量
    uint64 public constant aiOracleCallbackGasLimit = 500_000; // default sd: 500k

    address public immutable provider;
    address public immutable aiOracleManager; //用于管理aiOracle调用流程

    uint256 public modelId;
    string public basePrompt;
    uint256 public totalSupply;
    bool public nsfw;
    address private defaultNFTOwner;
    BitMaps.BitMap private _firstOwnershipChange; //记录某个nft是否完成初次ownership变更

    mapping(bytes prompt => uint256) promptToTokenId;
    mapping(uint256 tokenId => uint256) public seedOf; // tokenId => prompt
    mapping(uint256 tokenId => bytes) public aigcDataOf; // tokenId 对应的aigcData

    mapping(uint256 tokenId => uint256) tokenIdToRequestId; // tokenId 对应的requestId

    // contractURI

    // todo: 整理哪些参数放constructor，哪些放initialize,
    // 所有nft collection都一样的参数放这？
    constructor(address _provider, address _aiOracleManager) {
        provider = _provider;
        aiOracleManager = _aiOracleManager;
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
            imageUrl = unRevealImageUrl;
        }
        string memory mediaData = NFTMetadataRenderer.tokenMediaData(imageUrl, "");
        string memory aigcInfo = NFTMetadataRenderer.tokenAIGCInfo(
            basePrompt,
            aigcType,
            string(aigcDataOf[tokenId]),
            proofType,
            Strings.toHexString(provider),
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
        bytes storage currentAigcData = aigcDataOf[tokenId];

        return IAIOracleManager(aiOracleManager).isTokenFinalized(address(this), tokenId)
            && keccak256(aigcData) == keccak256(currentAigcData);
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

    /* royalty */
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) public onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
    }

    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) public onlyOwner {
        _setTokenRoyalty(tokenId, receiver, feeNumerator);
    }
}
