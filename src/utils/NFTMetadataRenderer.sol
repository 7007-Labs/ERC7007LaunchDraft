// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";

/**
 * @title NFTMetadataRenderer
 * @notice Library for generating and encoding NFT metadata in JSON format with base64 encoding
 */
library NFTMetadataRenderer {
    /// @notice Creates complete metadata string for an NFT including name, description, media data and AIGC info
    /// @param name The name of the NFT
    /// @param description A text description of the NFT
    /// @param mediaData The media data string containing image and/or animation URLs
    /// @param aigcInfo The AI-generated content information string
    /// @return A base64 encoded metadata URI string containing the complete NFT metadata
    function createMetadata(
        string memory name,
        string memory description,
        string memory mediaData,
        string memory aigcInfo
    ) internal pure returns (string memory) {
        bytes memory json = createMetadataJSON(name, description, mediaData, aigcInfo);
        return encodeMetadataJSON(json);
    }

    /// @notice Creates a JSON metadata string combining name, description, media data and AIGC info
    /// @param name The name of the NFT
    /// @param description A text description of the NFT
    /// @param mediaData The media data string containing image and/or animation URLs
    /// @param aigcInfo The AI-generated content information string
    /// @return Raw JSON metadata as bytes
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

    /// @notice Encodes JSON metadata into a base64 data URI format
    /// @param json The raw JSON metadata to encode
    /// @return A base64 encoded data URI string prefixed with "data:application/json;base64,"
    function encodeMetadataJSON(
        bytes memory json
    ) internal pure returns (string memory) {
        return string(abi.encodePacked("data:application/json;base64,", Base64.encode(json)));
    }

    /// @notice Generates a media data string containing image and/or animation URLs
    /// @param imageUrl The URL of the NFT's image
    /// @param animationUrl The URL of the NFT's animation
    /// @return A formatted string containing the media URLs with appropriate JSON keys
    /// @dev Returns empty string if both URLs are empty, includes only non-empty URLs in output
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

    /// @notice Creates a formatted string containing AI-generated content information
    /// @param prompt The prompt used to generate the content
    /// @param aigcType The type of AI-generated content
    /// @param aigcData Additional AI generation data
    /// @param proofType The type of proof for the AI generation
    /// @param provider The AI service provider
    /// @param modelId The ID of the AI model used
    /// @return A formatted string containing all AIGC-related information with appropriate JSON keys
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

    /// @notice Creates and encodes a contract-level URI metadata JSON
    /// @param name The name of the contract/collection
    /// @param description A description of the contract/collection
    /// @return A base64 encoded data URI string containing the contract metadata
    function encodeContractURIJSON(
        string memory name,
        string memory description
    ) internal pure returns (string memory) {
        return
            string(encodeMetadataJSON(abi.encodePacked('{"name": "', name, '", "description": "', description, '"}')));
    }
}
