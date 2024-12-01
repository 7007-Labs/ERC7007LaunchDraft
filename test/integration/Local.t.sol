// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console} from "forge-std/Test.sol";

import {ICurve} from "../../src/interfaces/ICurve.sol";
import {ERC7007Launch} from "../../src/ERC7007Launch.sol";
import {IntegrationBase} from "./IntegrationBase.t.sol";

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

    // function testFuzz_launch(
    //     uint24 _random
    // ) public {
    //     _configRand(_random);
    // }
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

    function testFuzz_Launch(
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

        bool isPresale = _randBool();
        uint256 fee;
        if (isPresale) {
            params.presaleMaxNum = uint32(_randUint(1, 7006));
            uint256 totalAmount = ICurve(bondingCurves[0].addr).getBuyPrice(0, uint256(params.presaleMaxNum));
            params.presalePrice =
                uint96((totalAmount + uint256(params.presaleMaxNum) - 1) / uint256(params.presaleMaxNum));
            params.presaleEnd = uint64(block.timestamp + 2 days);
            params.presaleMerkleRoot = usersMerkleRoot;
        } else {
            uint256 initialBuyNum = _randUint(1, 500);
            params.initialBuyNum = uint32(initialBuyNum);
            fee = erc7007LaunchProxy.estimateLaunchFee(params, aiOracle, randOracle);
        }

        vm.deal(user1, 2 ether);

        vm.prank(user1);
        erc7007LaunchProxy.launch(params, user1Proof);
    }
}
