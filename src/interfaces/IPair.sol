// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PairType} from "../enums/PairType.sol";
import {PairVariant} from "../enums/PairVariant.sol";

interface IPair {
    function getAssetRecipient() external returns (address);

    function changeAssetRecipient(
        address payable newRecipient
    ) external;

    function pairType() external view returns (PairType);

    function pairVariant() external view returns (PairVariant);

    function token() external view returns (address _token);

    function nft() external view returns (address);

    function owner() external view returns (address);

    function getBuyNFTQuote(
        uint256 assetId,
        uint256 numItems
    ) external view returns (uint256 inputAmount, uint256 aiAmount, uint256 royaltyAmount);

    function getSellNFTQuote(
        uint256 assetId,
        uint256 numItems
    ) external view returns (uint256 outputAmount, uint256 royaltyAmount);

    function swapTokenForNFTs(
        uint256 nftNum,
        uint256[] calldata desiredTokenIds,
        bool allowBuyOtherNFTs,
        uint256 maxExpectedTokenInput,
        address nftRecipient,
        bool isRouter,
        address routerCaller
    ) external payable returns (uint256 nftNumOutput, uint256 tokenInput);

    function swapNFTsForToken(
        uint256[] calldata tokenIds,
        uint256 minExpectedTokenOutput,
        address payable tokenRecipient,
        bool isRouter,
        address routerCaller
    ) external returns (uint256 tokenOutput);
}
