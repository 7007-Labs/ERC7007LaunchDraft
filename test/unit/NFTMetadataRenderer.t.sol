// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {NFTMetadataRenderer} from "../../src/utils/NFTMetadataRenderer.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";

contract NFTMetadataRendererTest is Test {
    function setUp() public {}

    function test_tokenMediaData() public {
        string memory s1 = NFTMetadataRenderer.tokenMediaData("https://example.com/image.png", "");
        assertEq(s1, 'image": "https://example.com/image.png", "');
        string memory s2 =
            NFTMetadataRenderer.tokenMediaData("https://example.com/image.png", "https://example.com/animation.png");
        assertEq(s2, 'image": "https://example.com/image.png", "animation_url": "https://example.com/animation.png", "');
    }

    function test_createMetadataJSON() public {
        string memory mediaData = NFTMetadataRenderer.tokenMediaData("https://example.com/image.png", "");

        string memory aigcInfo =
            NFTMetadataRenderer.tokenAIGCInfo("prompt", "aigcType", "aigcData", "proofType", "provider", "modelId");

        bytes memory metadataJSON = NFTMetadataRenderer.createMetadataJSON("name", "description", mediaData, aigcInfo);

        assertEq(
            metadataJSON,
            '{"name": "name", "description": "description", "image": "https://example.com/image.png", "prompt": "prompt", "aigc_type": "aigcType", "aigc_data": "aigcData", "proof_type": "proofType", "provider": "provider", "modelId": "modelId"}'
        );
    }
}
