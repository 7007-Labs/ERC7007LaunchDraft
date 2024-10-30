import {AIOracleCallbackReceiver} from "./libraries/AIOracleCallbackReceiver.sol";
import {IAIOracle} from "./interfaces/IAIOracle.sol";
import {IAIOracleManager} from "./interfaces/IAIOracleManager.sol";
import {ORAERC7007ImplV2} from "./nft/ORAERC7007ImplV2.sol";
import {ORAUtils} from "./utils/ORAUtils.sol";
import {IERC7007Updatable} from "./interfaces/IERC7007Updatable.sol";

contract AIOracleManager is IAIOracleManager, AIOracleCallbackReceiver {
    struct RequestInfo {
        address nft;
        bool isCallbacked;
        uint256[] tokenIds;
    }

    // nft => tokenId => seed
    mapping(address => mapping(uint256 => uint256)) nftSeeds;
    // nft => tokenId => requestId
    mapping(address => mapping(uint256 => uint256)) tokenIdToRequestId;
    mapping(uint256 requestId => RequestInfo) requests;

    constructor(
        IAIOracle _aiOracle
    ) AIOracleCallbackReceiver(_aiOracle) {}

    function getSeed(
        uint256 tokenId
    ) public returns (uint256) {
        return tokenId;
    }

    function reveal(address nft, uint256[] memory tokenIds) external payable {
        uint256 size = tokenIds.length;
        require(size > 0);
        bytes[] memory prompts = new bytes[](size);

        string memory basePrompt = ORAERC7007ImplV2(nft).basePrompt();
        uint256 modelId = ORAERC7007ImplV2(nft).modelId();

        bytes memory batchPrompt = "[";
        for (uint256 i = 0; i < size; i++) {
            if (i > 0) {
                batchPrompt = bytes.concat(batchPrompt, ",");
            }
            uint256 seed = getSeed(tokenIds[i]);
            nftSeeds[nft][tokenIds[i]] = seed;

            bytes memory prompt = ORAUtils.buildPrompt(basePrompt, seed);
            prompts[i] = prompt;
            batchPrompt = bytes.concat(batchPrompt, prompt);
        }
        batchPrompt = bytes.concat(batchPrompt, "]");

        uint64 gasLimit = getGasLimit(tokenIds.length);
        uint256 requestId = aiOracle.requestBatchInference{value: msg.value}(
            size, modelId, bytes(batchPrompt), address(this), gasLimit, "", IAIOracle.DA.Calldata, IAIOracle.DA.Calldata
        );
        for (uint256 i = 0; i < size; i++) {
            tokenIdToRequestId[nft][tokenIds[i]] = requestId;
        }
        requests[requestId] = RequestInfo({nft: nft, isCallbacked: false, tokenIds: tokenIds});
    }

    function getGasLimit(
        uint256 num
    ) internal pure returns (uint64) {
        return uint64(100 * num);
    }

    // 估算调用aiOracle需要的费用
    function estimateFee(address nft, uint256 num) public view returns (uint256) {
        uint256 modelId = ORAERC7007ImplV2(nft).modelId();
        return aiOracle.estimateFeeBatch(modelId, getGasLimit(num), num);
    }

    function aiOracleCallback(
        uint256 requestId,
        bytes calldata output,
        bytes calldata /* callbackData */
    ) external override onlyAIOracleCallback {
        RequestInfo storage info = requests[requestId];
        uint256 tokenIdsNum = info.tokenIds.length;
        require(tokenIdsNum > 0);

        bytes[] memory cids = ORAUtils.decodeCIDs(output);
        require(tokenIdsNum == cids.length);

        string memory basePrompt = ORAERC7007ImplV2(info.nft).basePrompt();
        for (uint256 i = 0; i < tokenIdsNum; i++) {
            uint256 tokenId = info.tokenIds[i];
            bytes memory prompt = ORAUtils.buildPrompt(basePrompt, nftSeeds[info.nft][tokenId]);
            if (info.isCallbacked) {
                IERC7007Updatable(info.nft).update(prompt, cids[i]);
            } else {
                IERC7007Updatable(info.nft).addAigcData(tokenId, prompt, cids[i], bytes(""));
            }
        }
    }

    function isTokenFinalized(address nft, uint256 tokenId) external view returns (bool) {
        uint256 requestId = tokenIdToRequestId[nft][tokenId];
        return aiOracle.isFinalized(requestId);
    }
}
