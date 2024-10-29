// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PairType} from "../enums/PairType.sol";
import {PairVariant} from "../enums/PairVariant.sol";

interface IPair {
    function getAssetRecipient() external returns (address);

    function changeAssetRecipient(address payable newRecipient) external;

    function pairType() external view returns (PairType);

    function pairVariant() external view returns (PairVariant);

    function token() external view returns (address _token);

    function nft() external view returns (address);

    function owner() external view returns (address);

    function getBuyNFTQuote(uint256 assetId, uint256 numItems)
        external
        view
        returns (uint256 inputAmount, uint256 royaltyAmount);

    function getSellNFTQuote(uint256 assetId, uint256 numItems)
        external
        view
        returns (uint256 outputAmount, uint256 royaltyAmount);

    function swapTokenForNFTs(
        uint256 nftNum,
        uint256[] calldata desiredTokenIds,
        uint256 maxExpectedTokenInput,
        address nftRecipient
    ) external payable returns (uint256);

    function swapNFTsForToken(
        uint256[] calldata tokenIds,
        uint256 minExpectedTokenOutput,
        address payable tokenRecipient
    ) external returns (uint256);
}
