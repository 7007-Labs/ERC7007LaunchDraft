// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";

/// NFT metadata library for rendering metadata associated with editions
library NFTMetadataRenderer {
    function createMetadata(
        string memory name,
        string memory description,
        string memory mediaData,
        string memory aigcInfo
    ) internal pure returns (string memory) {
        bytes memory json = createMetadataJSON(name, description, mediaData, aigcInfo);
        return encodeMetadataJSON(json);
    }

    function createMetadataJSON(
        string memory name,
        string memory description,
        string memory mediaData,
        string memory aigcInfo
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            '{"name": "', name, '", "', 'description": "', description, '", "', mediaData, aigcInfo, '"}'
        );
    }

    /// Encodes the argument json bytes into base64-data uri format
    /// @param json Raw json to base64 and turn into a data-uri
    function encodeMetadataJSON(
        bytes memory json
    ) internal pure returns (string memory) {
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(json)));
    }

    /// Generates edition metadata from storage information as base64-json blob
    /// Combines the media data and metadata
    /// @param imageUrl URL of image to render for edition
    /// @param animationUrl URL of animation to render for edition
    function tokenMediaData(string memory imageUrl, string memory animationUrl) internal pure returns (string memory) {
        bool hasImage = bytes(imageUrl).length > 0;
        bool hasAnimation = bytes(animationUrl).length > 0;
        if (hasImage && hasAnimation) {
            return string(abi.encodePacked('image": "', imageUrl, '", "animation_url": "', animationUrl, '", "'));
        }
        if (hasImage) {
            return string(abi.encodePacked('image": "', imageUrl, '", "'));
        }
        if (hasAnimation) {
            return string(abi.encodePacked('animation_url": "', animationUrl, '", "'));
        }

        return "";
    }

    function tokenAIGCInfo(
        string memory prompt,
        string memory aigcType,
        string memory aigcData,
        string memory proofType,
        string memory provider,
        string memory modelId
    ) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                'prompt": "',
                prompt,
                '", "aigc_type": "',
                aigcType,
                '", "aigc_data": "',
                aigcData,
                '", "proof_type": "',
                proofType,
                '", "provider": "',
                provider,
                '", "modelId": "',
                modelId
            )
        );
    }

    function encodeContractURIJSON(
        string memory name,
        string memory description
    ) internal pure returns (string memory) {
        return
            string(encodeMetadataJSON(abi.encodePacked('{"name": "', name, '", "description": "', description, '"}')));
    }
}
