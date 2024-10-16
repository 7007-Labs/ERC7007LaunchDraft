// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC2309} from "@openzeppelin/contracts/interfaces/IERC2309.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";

import {ERC721RoyaltyUpgradeable} from
    "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721RoyaltyUpgradeable.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {AIOracleCallbackReceiver} from "ora/AIOracleCallbackReceiver.sol";
import {IAIOracle} from "ora/interfaces/IAIOracle.sol";
import {IERC7007Updatable} from "../interfaces/IERC7007Updatable.sol";
import {NFTMetadataRenderer} from "../utils/NFTMetadataRenderer.sol";

// todo: 使用openzeppelin的ERC721部分优化，等完善测试后进行
contract ORAERC7007Impl is ERC721RoyaltyUpgradeable, IERC4906, IERC2309, IERC7007Updatable, AIOracleCallbackReceiver {
    using BitMaps for BitMaps.BitMap;

    address public owner;
    uint256 public modelId;
    string public basePrompt;
    bool public nsfw;

    uint256 public totalSupply;
    address public pair; // 交易对Address，todo: 如果reveal函数的权限控制方式改变，此变量可去除
    address public aiOracleManager; //用于管理aiOracle调用流程

    address private defaultNFTOwner; // nft owner
    BitMaps.BitMap private _firstOwnershipChange; //记录某个nft是否完成初次ownership变更

    string public constant unRevealImageURI = "ipfs://xxx"; //todo: 默认图片链接
    uint64 public constant aiOracleCallbackGasLimit = 500000; // default sd: 500k

    mapping(uint256 tokenId => uint256) requestIdOf; // tokenId 对应的requestId
    mapping(uint256 tokenId => bytes) aigcDataOf; // tokenId 对应的aigcData
    mapping(uint256 tokenId => bytes) promptOf; // tokenId 对应的prompt
    mapping(uint256 requestId => uint256) requests; // requestId => tokenId
    mapping(bytes32 promptHash => uint256) promptHashToRequestId;

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    // todo: 整理哪些参数放constructor，哪些放initialize,
    // 所有nft collection都一样的参数放这？
    constructor(IAIOracle _aiOracle) initializer AIOracleCallbackReceiver(_aiOracle) {}

    function initialize(
        string memory name,
        string memory symbol,
        address _owner,
        uint256 _totalSupply,
        address _defaultNFTOwner,
        string memory _basePrompt,
        uint256 _modelId,
        address _pair,
        bool _nsfw
    ) public initializer {
        __ERC721_init(name, symbol);
        owner = _owner;
        totalSupply = _totalSupply;
        modelId = _modelId;
        pair = _pair;
        aiOracleManager = address(this); // todo: 考虑模块化
        basePrompt = _basePrompt;
        nsfw = _nsfw;

        // todo: 模块化
        defaultNFTOwner = _defaultNFTOwner;
        _increaseBalance(_defaultNFTOwner, uint128(_totalSupply));
        emit ConsecutiveTransfer(0, _totalSupply - 1, address(0), _defaultNFTOwner);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        string memory imageURI;
        if (aigcDataOf[tokenId].length > 0) {
            imageURI = string.concat("ipfs://", string(aigcDataOf[tokenId]));
        } else {
            imageURI = unRevealImageURI;
        }
        // todo: 适配metadata内容
        return NFTMetadataRenderer.createMetadataAIGC(
            name(),
            "", //todo: description
            imageURI,
            "",
            0,
            0
        );
    }

    /* 涉及到batchMint相关优化逻辑 */
    // todo: 可以模块化
    function _ownerOf(uint256 tokenId) internal view override returns (address) {
        if (_firstOwnershipChange.get(tokenId) == false) {
            return defaultNFTOwner;
        }
        return super._ownerOf(tokenId);
    }

    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        if (_firstOwnershipChange.get(tokenId) == false) {
            _firstOwnershipChange.set(tokenId);
        }
        return super._update(to, tokenId, auth);
    }

    /* ERC7007  */
    // 调用这个函数来完成数据的绑定
    // 此处修改了一些修饰符，但不影响对interface的兼容
    // 注意此函数只能被调用一次
    function addAigcData(uint256 tokenId, bytes memory prompt, bytes memory aigcData, bytes memory proof) external {
        require(msg.sender == aiOracleManager, "Only aiOracleManager");
        require(aigcDataOf[tokenId].length == 0, "AigcData exists");

        aigcDataOf[tokenId] = aigcData;
        emit AigcData(tokenId, prompt, aigcData, proof);

        emit MetadataUpdate(tokenId);
    }

    // opML情况下，只检查数据是否finalized和aigcData是否最新的
    function verify(bytes calldata prompt, bytes calldata aigcData, bytes calldata /* proof */ )
        external
        view
        override
        returns (bool success)
    {
        uint256 requestId = promptHashToRequestId[keccak256(prompt)];
        uint256 tokenId = requests[requestId];
        bytes storage currentAigcData = aigcDataOf[tokenId];
        return aiOracle.isFinalized(requestId) && keccak256(aigcData) == keccak256(currentAigcData);
    }

    function update(bytes calldata prompt, bytes calldata aigcData) external {
        require(msg.sender == aiOracleManager, "Only aiOracleManager");
        uint256 requestId = promptHashToRequestId[keccak256(prompt)];
        uint256 tokenId = requests[requestId];
        aigcDataOf[tokenId] = aigcData;

        emit Update(tokenId, prompt, aigcData);
        emit MetadataUpdate(tokenId);
    }

    /* aiOracleManager */
    // reveal nft metadata
    function reveal(uint256 tokenId) external payable {
        // todo: 改成初次售出后任意用户可以调用,理论上pair会判断是否初次交易，如果是初次交易，就会调用此函数
        require(msg.sender == pair, "Only Pair can reveal");
        require(requestIdOf[tokenId] == 0, "Should only call once");

        // todo: prompt = baseprompt + salt
        bytes memory prompt = "";

        // todo: 考虑此处防重入?
        uint256 requestId = aiOracle.requestCallback{value: msg.value}(
            modelId, bytes(prompt), address(this), aiOracleCallbackGasLimit, ""
        );
        // todo: 合并结构?
        requestIdOf[tokenId] = requestId;
        requests[requestId] = tokenId;
        promptOf[tokenId] = prompt;
        promptHashToRequestId[keccak256(prompt)] = requestId;
    }

    // 估算调用aiOracle需要的费用
    function estimateFee() public view returns (uint256) {
        return aiOracle.estimateFee(modelId, aiOracleCallbackGasLimit);
    }

    // 注意此函数在opML下可能会被多次调用
    function aiOracleCallback(uint256 requestId, bytes calldata output, bytes calldata /* callbackData */ )
        external
        override
        onlyAIOracleCallback
    {
        // todo: 检查requestId
        uint256 tokenId = requests[requestId];
        bytes storage prompt = promptOf[tokenId];
        if (aigcDataOf[tokenId].length == 0) {
            this.addAigcData(tokenId, prompt, output, bytes(""));
        } else {
            this.update(prompt, output);
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
