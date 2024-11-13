// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {MockAIOracle} from "../mocks/MockAIOracle.t.sol";
import {MockRandOracle} from "../mocks/MockRandOracle.t.sol";
import {IAIOracle} from "../../src/interfaces/IAIOracle.sol";
import {IRandOracle} from "../../src/interfaces/IRandOracle.sol";
import {ORAERC7007Impl} from "../../src/nft/ORAERC7007ImplWithRandOracle.sol";

contract CustomERC7007Impl is ORAERC7007Impl {
    constructor(IAIOracle _aiOracle, IRandOracle _randOracle) ORAERC7007Impl(_aiOracle, _randOracle) {}

    function setPrompt(
        string memory newPrompt
    ) external {
        basePrompt = newPrompt;
    }
}

contract NFTFeeEstimate is Test {
    address aiOracle;
    address randOracle;
    CustomERC7007Impl public nft;

    address owner = makeAddr("owner");
    address operator = makeAddr("operator");
    uint256 constant MODEL_ID = 50;
    uint256 constant TOTAL_SUPPLY = 100;

    function setUp() public {
        aiOracle = address(new MockAIOracle());
        randOracle = address(new MockRandOracle());
        CustomERC7007Impl impl = new CustomERC7007Impl(IAIOracle(aiOracle), IRandOracle(randOracle));

        nft = CustomERC7007Impl(Clones.cloneDeterministic(address(impl), keccak256("nft")));
        ORAERC7007Impl.CollectionMetadata memory metadata = ORAERC7007Impl.CollectionMetadata({
            name: "Test NFT",
            symbol: "TEST",
            description: "Test Description",
            prompt: "Test Prompt",
            nsfw: false
        });
        nft.initialize(metadata, owner, MODEL_ID);
        nft.activate(TOTAL_SUPPLY, owner, operator);
    }

    function test_Activate() public {
        assertEq(nft.totalSupply(), TOTAL_SUPPLY);
    }

    function generateBytes(
        uint256 length
    ) public pure returns (bytes memory) {
        bytes memory result = new bytes(length);

        for (uint256 i = 0; i < length; i++) {
            // 这里使用0x61 ("a")作为示例
            result[i] = 0x61;
        }

        return result;
    }

    function testFuzz_aiOracleCallback(
        uint256 promptLength
    ) public {
        // 计算aiOracleCallback所需的gaslimit
        promptLength = bound(promptLength, 10, 300);
        string memory newPrompt = string(generateBytes(promptLength));
        nft.setPrompt(newPrompt);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 7006;

        vm.deal(operator, 10 ether);
        vm.prank(operator);
        nft.reveal{value: 1 ether}(tokenIds);
        bytes32 requestId = keccak256(abi.encodePacked(tokenIds));

        uint256 fakeAiOracleRequestId = 1014;
        bytes memory output = MockAIOracle(aiOracle).makeOutput(1);
        bytes memory callbackData = abi.encode(requestId);

        vm.prank(aiOracle);
        // gas cost 137371
        nft.aiOracleCallback(fakeAiOracleRequestId, output, callbackData);
    }

    function testFuzz_awaitRandOracle(
        uint256 promptLength
    ) public {
        //测试randOracle回调所需的gaslimit
        promptLength = bound(promptLength, 10, 300);
        string memory newPrompt = string(generateBytes(promptLength));
        nft.setPrompt(newPrompt);
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 7006;

        vm.deal(operator, 10 ether);
        vm.prank(operator);
        nft.reveal{value: 1 ether}(tokenIds);
        bytes32 requestId = keccak256(abi.encodePacked(tokenIds));

        uint256 fakeRandOracleRequestId = 1014;
        uint256 randNum = 23_412_423_141;
        bytes memory callbackData = abi.encode(requestId);

        vm.prank(randOracle);
        // gas cost 250282
        nft.awaitRandOracle(fakeRandOracleRequestId, randNum, callbackData);

        bytes memory aiOracleOutput = MockAIOracle(aiOracle).makeOutput(1);
        MockAIOracle(aiOracle).invokeCallback(0, aiOracleOutput);
    }

    function test_fee() public {
        uint256 gasPrice = 10 gwei;
        uint256 gas = 250_282 + 137_371;
        uint256 aiModelFee = 0.0003 ether;
        uint256 randModelFee = 0.000003 ether;
        uint256 totalCost = gas * gasPrice + aiModelFee + randModelFee;
        uint256 ethUSDPrice = 3000;
        console2.log("fee(USD): ", totalCost * ethUSDPrice / (1e18)); // 12
    }
    /*
    function test_AIOracle_FeeEstimate() public {
        uint256 batchSize = 5;
        uint64 gasLimit = nft.getGasLimit(batchSize);
        uint256 expectedFee = MockAIOracle(aiOracle).estimateFeeBatch(MODEL_ID, gasLimit, batchSize);

        uint256[] memory tokenIds = new uint256[](batchSize);
        for (uint256 i = 0; i < batchSize; i++) {
            tokenIds[i] = i;
        }

        bytes32 requestId = keccak256(abi.encodePacked(tokenIds));
        vm.startPrank(operator);
        uint256 fee = nft.estimateRevealFee(batchSize);
        vm.stopPrank();

        // Fee should include both AI oracle and rand oracle fees
        assertGt(fee, expectedFee);
    }

    function test_AIOracle_Callback() public {
        uint256 batchSize = 2;
        uint256[] memory tokenIds = new uint256[](batchSize);
        for (uint256 i = 0; i < batchSize; i++) {
            tokenIds[i] = i;
        }

        bytes32 requestId = keccak256(abi.encodePacked(tokenIds));
        uint256 fee = nft.estimateRevealFee(batchSize);

        // Start reveal process
        vm.startPrank(operator);
        vm.deal(operator, fee);
        nft.reveal{value: fee}(tokenIds);
        vm.stopPrank();

        // Simulate rand oracle callback which triggers AI oracle request
        bytes memory randOutput = abi.encode(uint256(123)); // Random seed
        MockRandOracle(randOracle).invokeCallback(0, randOutput);

        // Simulate AI oracle callback
        bytes memory aiOutput = MockAIOracle(aiOracle).makeOutput(batchSize);
        MockAIOracle(aiOracle).invokeCallback(0, aiOutput);

        // Verify NFT metadata was updated
        for (uint256 i = 0; i < batchSize; i++) {
            bytes memory aigcData = nft.aigcDataOf(tokenIds[i]);
            assertGt(aigcData.length, 0, "AIGC data should be set");
        }
    }

    function test_AIOracle_Callback_UpdatesTokenURI() public {
        uint256 batchSize = 1;
        uint256[] memory tokenIds = new uint256[](batchSize);
        tokenIds[0] = 0;

        bytes32 requestId = keccak256(abi.encodePacked(tokenIds));
        uint256 fee = nft.estimateRevealFee(batchSize);

        // Get initial token URI
        string memory initialURI = nft.tokenURI(0);

        // Start reveal process
        vm.startPrank(operator);
        vm.deal(operator, fee);
        nft.reveal{value: fee}(tokenIds);
        vm.stopPrank();

        // Simulate oracle callbacks
        MockRandOracle(randOracle).invokeCallback(0, abi.encode(uint256(123)));
        bytes memory aiOutput = MockAIOracle(aiOracle).makeOutput(batchSize);
        MockAIOracle(aiOracle).invokeCallback(0, aiOutput);

        // Verify token URI was updated
        string memory newURI = nft.tokenURI(0);
        assertTrue(keccak256(bytes(initialURI)) != keccak256(bytes(newURI)), "Token URI should be updated after reveal");
    }
    */
}
