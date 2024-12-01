// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console} from "forge-std/Test.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {ICurve} from "../../src/interfaces/ICurve.sol";
import {IPair} from "../../src/interfaces/IPair.sol";
import {ERC7007Launch} from "../../src/ERC7007Launch.sol";
import {IntegrationBase} from "./IntegrationBase.t.sol";
import {MockAIOracle} from "../mocks/MockAIOracle.t.sol";
import {MockRandOracle} from "../mocks/MockRandOracle.t.sol";
import {Solarray} from "../utils/Solarray.sol";

contract Integration_Local is IntegrationBase {
    string[] public prompts = [
        // 18 bytes
        "cute puppy, fluffy",
        // 113 bytes
        "adorable golden retriever puppy playing in grass, sunny day, soft fur, big eyes, playful expression, high quality",
        // 218 bytes
        "a photorealistic portrait of a happy Corgi puppy sitting in a flower garden, morning sunlight, detailed fur texture, sparkling eyes, pink tongue, natural background, professional photography, 8k resolution, high detail",
        // 336 bytes
        "an ultra-detailed photograph of a charming Husky puppy in a snowy landscape, crystal clear blue eyes, perfectly groomed fluffy white and grey fur, wearing a tiny red scarf, snowflakes falling around, golden hour lighting, sharp focus on facial features, professional camera settings, depth of field effect, award-winning pet photography"
    ];

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");
    address user4 = makeAddr("user4");
    bytes32 usersMerkleRoot = 0x585f9f8d790909047a9ac2fccd78a4de668596df1d7cf579bd6a9fda19211036;
    bytes32[] user1Proof = [
        bytes32(0xc471bda26e2e9f486b58f8f86bf6b700bb9d0db6dafabec4ee3f352a216fc396),
        bytes32(0x3457fcb5d46c166f9e5742d81aef337030c0bb10f0fbc23bb39da8c6b9e08b4c)
    ];
    bytes32[] user2Proof = [
        bytes32(0x83a81a15f71c60ce0f7ebed1c3ef158329975b28013c5fa91a666413b145287b),
        bytes32(0xcbc3414f08bcfe1a4a5dea214e4c4cc09ea137e41c2c99c7f42c3bf752e335d9)
    ];
    bytes32[] user3Proof = [
        bytes32(0x4e2ef3f4d279d23ce0933035d8c8fb3ce41acb03aa29a326c527a6c76b912f6e),
        bytes32(0xcbc3414f08bcfe1a4a5dea214e4c4cc09ea137e41c2c99c7f42c3bf752e335d9)
    ];
    bytes32[] user4Proof = [
        bytes32(0x9abe6538df951915d55c9917d0f7e1aa3bb7be7dcdb0adec0025066572b270b2),
        bytes32(0x3457fcb5d46c166f9e5742d81aef337030c0bb10f0fbc23bb39da8c6b9e08b4c)
    ];

    function testFuzz_Launch_WithPresale(
        uint24 _random
    ) public {
        _configRand(_random);

        vm.prank(admin);
        erc7007LaunchProxy.setWhitelistMerkleRoot(usersMerkleRoot);

        ERC7007Launch.LaunchParams memory params;
        uint256 promptIndex = _randUint(0, 3);
        string memory prompt = prompts[promptIndex];
        params.prompt = prompt;
        bool nsfw = _randBool();
        params.metadataInitializer = abi.encode("TEST NFT", "TNFT", "erc7007 nft description", nsfw);
        params.provider = address(aiOracle);
        params.providerParams = abi.encode(50);
        params.bondingCurve = bondingCurves[0].addr;

        params.presaleMaxNum = uint32(_randUint(1, 7006));
        uint256 totalAmount = ICurve(bondingCurves[0].addr).getBuyPrice(0, uint256(params.presaleMaxNum));
        params.presalePrice = uint96((totalAmount + uint256(params.presaleMaxNum) - 1) / uint256(params.presaleMaxNum));
        params.presaleEnd = uint64(block.timestamp + 2 days);
        params.presaleMerkleRoot = usersMerkleRoot;

        vm.prank(user1);
        address pair = erc7007LaunchProxy.launch(params, user1Proof);
        address nft = IPair(pair).nft();
        assertEq(IPair(pair).owner(), user1);

        uint256 amount;
        vm.deal(user2, 1 ether);
        vm.startPrank(user2);
        (amount,,) = IPair(pair).getPresaleQuote(0, 1);
        erc7007LaunchProxy.purchasePresaleNFTs{value: amount + 123}(pair, 1, 1 ether, user2, user2Proof, user2Proof);
        vm.stopPrank();
        assertEq(user2.balance, 1 ether - amount);

        vm.warp(block.timestamp + 3 days);

        uint256 nftNum = _randUint(2, 100);
        (amount,,) = IPair(pair).getBuyNFTQuote(0, nftNum, false);
        vm.prank(user2);
        erc7007LaunchProxy.swapTokenForNFTs{value: amount}(pair, nftNum, amount, user2, user2Proof);

        uint256[] memory tokenIds = new uint256[](nftNum);
        uint256 count = 0;
        for (uint256 i; i < nftNum; i++) {
            if (_randBool()) {
                tokenIds[count] = i;
                count++;
            }
        }
        if (count == 0) {
            tokenIds[count] = 0;
            count++;
        }
        assembly {
            mstore(tokenIds, count)
        }

        vm.prank(user2);
        IERC721(nft).setApprovalForAll(pair, true);

        (amount,) = IPair(pair).getSellNFTQuote(0, tokenIds.length);
        vm.prank(user2);
        erc7007LaunchProxy.swapNFTsForToken(pair, tokenIds, amount, payable(user2), user2Proof);

        (amount,,) = IPair(pair).getBuyNFTQuote(0, tokenIds.length, true);
        vm.deal(user3, 1 ether);

        vm.prank(user3);
        erc7007LaunchProxy.swapTokenForSpecificNFTs{value: amount}(
            pair, tokenIds, tokenIds.length, amount, user3, user3Proof
        );

        _invokeRandOracle();
        _invokeAIOracle();
    }

    function testFuzz_Launch_WithoutPresale(
        uint24 _random
    ) public {
        _configRand(_random);

        vm.prank(admin);
        erc7007LaunchProxy.setWhitelistMerkleRoot(usersMerkleRoot);

        ERC7007Launch.LaunchParams memory params;
        uint256 promptIndex = _randUint(0, 3);
        string memory prompt = prompts[promptIndex];
        params.prompt = prompt;
        bool nsfw = _randBool();
        params.metadataInitializer = abi.encode("TEST NFT", "TNFT", "erc7007 nft description", nsfw);
        params.provider = address(aiOracle);
        params.providerParams = abi.encode(50);
        params.bondingCurve = bondingCurves[0].addr;
        params.initialBuyNum = _randUint(1, 300);

        uint256 amount;
        amount = erc7007LaunchProxy.estimateLaunchFee(params, aiOracle, randOracle);

        vm.deal(user1, 1 ether);
        vm.prank(user1);
        address pair = erc7007LaunchProxy.launch{value: amount}(params, user1Proof);
        address nft = IPair(pair).nft();
        assertEq(IPair(pair).owner(), user1);

        uint256 nftNum = _randUint(2, 100);
        vm.deal(user2, 1 ether);
        (amount,,) = IPair(pair).getBuyNFTQuote(0, nftNum, false);
        vm.prank(user2);
        erc7007LaunchProxy.swapTokenForNFTs{value: amount}(pair, nftNum, amount, user2, user2Proof);

        uint256[] memory tokenIds = new uint256[](nftNum);
        uint256 startTokenId = params.initialBuyNum;
        uint256 count = 0;
        for (uint256 i = startTokenId; i < nftNum; i++) {
            if (_randBool()) {
                tokenIds[count] = i;
                count++;
            }
        }
        if (count == 0) {
            tokenIds[count] = startTokenId;
            count++;
        }
        assembly {
            mstore(tokenIds, count)
        }

        vm.prank(user2);
        IERC721(nft).setApprovalForAll(pair, true);

        (amount,) = IPair(pair).getSellNFTQuote(0, tokenIds.length);
        vm.prank(user2);
        erc7007LaunchProxy.swapNFTsForToken(pair, tokenIds, amount, payable(user2), user2Proof);

        (amount,,) = IPair(pair).getBuyNFTQuote(0, tokenIds.length, true);
        vm.deal(user3, 1 ether);

        vm.prank(user3);
        erc7007LaunchProxy.swapTokenForSpecificNFTs{value: amount}(
            pair, tokenIds, tokenIds.length, amount, user3, user3Proof
        );

        _invokeRandOracle();
        _invokeAIOracle();
    }

    function _invokeRandOracle() internal {
        uint256 count = MockRandOracle(randOracle).latestRequestId();
        for (uint256 i = 1; i <= count; i++) {
            uint256 seed = _randUint(1, type(uint128).max);
            MockRandOracle(randOracle).invoke(i, abi.encodePacked(seed), "");
        }
    }

    function _invokeAIOracle() internal {
        uint256 randOracleCount = MockRandOracle(randOracle).latestRequestId();
        uint256 count = MockAIOracle(aiOracle).latestRequestId();
        require(randOracleCount == count, "oracle request num is wrong");
        for (uint256 i = 1; i <= count; i++) {
            bytes memory output = MockAIOracle(aiOracle).makeRequestOutput(i);
            MockAIOracle(aiOracle).invokeCallback(i, output);
        }
    }
}
