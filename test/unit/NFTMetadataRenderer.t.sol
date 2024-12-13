// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {NFTMetadataRenderer} from "../../src/utils/NFTMetadataRenderer.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";

contract NFTMetadataRendererTest is Test {
    function setUp() public {}

    function test_tokenMediaData() public pure {
        string memory s1 = NFTMetadataRenderer.tokenMediaData("https://example.com/image.png", "");
        assertEq(s1, 'image": "https://example.com/image.png", "');
        string memory s2 =
            NFTMetadataRenderer.tokenMediaData("https://example.com/image.png", "https://example.com/animation.png");
        assertEq(s2, 'image": "https://example.com/image.png", "animation_url": "https://example.com/animation.png", "');
    }

    function test_createMetadataJSON() public pure {
        string memory mediaData = NFTMetadataRenderer.tokenMediaData("https://example.com/image.png", "");

        string memory aigcInfo =
            NFTMetadataRenderer.tokenAIGCInfo("prompt", 10, "aigcType", "aigcData", "proofType", "provider", "modelId");

        bytes memory metadataJSON = NFTMetadataRenderer.createMetadataJSON("name", "description", mediaData, aigcInfo);

        assertEq(
            metadataJSON,
            '{"name": "name", "description": "description", "image": "https://example.com/image.png", "prompt": "prompt", "seed": 10, "aigc_type": "aigcType", "aigc_data": "aigcData", "proof_type": "proofType", "provider": "provider", "modelId": "modelId"}'
        );
    }

    function test_encodeContractURIJSON() public pure {
        string memory data = NFTMetadataRenderer.encodeContractURIJSON("name", "description");
        assertEq(data, "data:application/json;base64,eyJuYW1lIjogIm5hbWUiLCAiZGVzY3JpcHRpb24iOiAiZGVzY3JpcHRpb24ifQ==");
    }
}
