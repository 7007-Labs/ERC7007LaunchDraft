// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {NFTMetadataRenderer} from "../src/utils/NFTMetadataRenderer.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {IAIOracle} from "../src/interfaces/IAIOracle.sol";
import {AIOracleManager} from "../src/AIOracleManager.sol";
import {ORAERC7007Impl} from "../src/nft/ORAERC7007Impl.sol";
import {ORAERC7007ImplV2} from "../src/nft/ORAERC7007ImplV2.sol";

contract MockAIOracle is IAIOracle {
    uint256 public constant MOCK_FEE = 0.01 ether;

    function estimateFee(uint256, uint256) external pure returns (uint256) {
        return MOCK_FEE;
    }

    function estimateFeeBatch(uint256, uint256, uint256) external pure returns (uint256) {
        return MOCK_FEE;
    }

    function requestCallback(
        uint256,
        bytes calldata,
        address,
        uint64,
        bytes calldata
    ) external payable returns (uint256) {
        // require(msg.value >= MOCK_FEE, "Insufficient fee");
        return 1; // Mock request ID
    }

    function requestCallback(
        uint256 modelId,
        bytes memory input,
        address callbackContract,
        uint64 gasLimit,
        bytes memory callbackData,
        DA inputDA,
        DA outputDA
    ) external payable returns (uint256) {
        return 1;
    }

    function requestBatchInference(
        uint256 batchSize,
        uint256 modelId,
        bytes memory input,
        address callbackContract,
        uint64 gasLimit,
        bytes memory callbackData,
        DA inputDA,
        DA outputDA
    ) external payable returns (uint256) {
        // require(msg.value >= MOCK_FEE, "Insufficient fee");
        return 1; // Mock request ID
    }

    function isFinalized(
        uint256
    ) external pure returns (bool) {
        return true; // Always return true for the mock
    }
}

contract AIGCTest is Test {
    IAIOracle aiOracle;
    AIOracleManager aiOracleManager;
    ORAERC7007Impl nftV1;
    ORAERC7007ImplV2 nftV2;
    bytes output = bytes(
        "\x00\x00\x00\x02\x00\x00\x00.QmY3GuNcscmzD6CnVjKWeqfSPaVXb2gck75HUrtq8Yf3su\x00\x00\x00.QmXwcj4rYofnQuZpjAsUmqPaDEkaJ7ZhwuLCRVgCarRSPN"
    );

    function setUp() public {
        aiOracle = new MockAIOracle();
        aiOracleManager = new AIOracleManager(aiOracle);
        ORAERC7007Impl impl1 = new ORAERC7007Impl(aiOracle);
        ERC1967Proxy proxy1 = new ERC1967Proxy(address(impl1), "");
        nftV1 = ORAERC7007Impl(address(proxy1));
        nftV1.initialize("name", "symbol", "_basePrompt", address(this), true, 50);
        nftV1.mintAll(address(2), 10);
        ORAERC7007ImplV2 impl2 = new ORAERC7007ImplV2(address(1), address(aiOracleManager));
        ERC1967Proxy proxy2 = new ERC1967Proxy(address(impl2), "");
        nftV2 = ORAERC7007ImplV2(address(proxy2));
        nftV2.initialize("name", "symbol", "_basePrompt", address(this), true, 50);
        nftV2.mintAll(address(2), 10);
    }

    function test_v1() public {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        uint256 start = gasleft();
        nftV1.reveal(tokenIds);
        vm.prank(address(aiOracle));
        nftV1.aiOracleCallback(1, output, "");
        uint256 cost = start - gasleft();
        console2.log("cost: ", cost); // 289927
    }

    function test_v2() public {
        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 1;
        tokenIds[1] = 2;
        uint256 start = gasleft();
        aiOracleManager.reveal(address(nftV2), tokenIds);
        vm.prank(address(aiOracle));
        aiOracleManager.aiOracleCallback(1, output, "");
        uint256 cost = start - gasleft();
        console2.log("cost: ", cost); // 319985
    }
}
