// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PairType} from "../enums/PairType.sol";
import {PairVariant} from "../enums/PairVariant.sol";
import {ICurve} from "./ICurve.sol";

interface IPair {
    /// @notice Sales configuration
    /// @dev Uses 3 storage slots
    struct SalesConfig {
        /// @notice Maximum number of NFTs an address can purchase during presale
        uint32 maxPresalePurchasePerAddress;
        /// @notice Maximum total NFTs that can be purchased during presale
        uint32 presaleMaxNum;
        /// @notice Presale start timestamp
        uint64 presaleStart;
        /// @notice Presale end timestamp
        uint64 presaleEnd;
        /// @notice Public sale start timestamp
        uint64 publicSaleStart;
        /// @notice The fixed price during presale period
        uint96 presalePrice;
        /// @notice The address of the bonding curve contract
        ICurve bondingCurve;
        /// @notice Merkle root for verifying presale eligibility
        bytes32 presaleMerkleRoot;
    }

    function pairType() external view returns (PairType);

    function pairVariant() external view returns (PairVariant);

    function token() external view returns (address _token);

    function nft() external view returns (address);

    function owner() external view returns (address);

    function getBuyNFTQuote(
        uint256 assetId,
        uint256 numItems,
        bool isPick
    ) external view returns (uint256 inputAmount, uint256 aigcAmount, uint256 royaltyAmount);

    function getSellNFTQuote(
        uint256 assetId,
        uint256 numItems
    ) external view returns (uint256 outputAmount, uint256 royaltyAmount);

    function getPresaleQuote(
        uint256 assetId,
        uint256 numItems
    ) external view returns (uint256 inputAmount, uint256 aigcAmount, uint256 royaltyAmount);

    function purchasePresale(
        uint256 nftNum,
        uint256 maxExpectedTokenInput,
        address nftRecipient,
        bytes32[] calldata merkleProof,
        bool isRouter,
        address routerCaller
    ) external payable returns (uint256 presaleNum, uint256 totalAmount);

    function swapTokenForNFTs(
        uint256 nftNum,
        uint256 maxExpectedTokenInput,
        address nftRecipient,
        bool isRouter,
        address routerCaller
    ) external payable returns (uint256 nftNumOutput, uint256 tokenInput);

    function swapTokenForSpecificNFTs(
        uint256[] calldata targetTokenIds,
        uint256 maxNFTNum,
        uint256 minNFTNum,
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
