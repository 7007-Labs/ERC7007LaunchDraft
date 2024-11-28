// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IPair} from "../../src/interfaces/IPair.sol";
import {PairType} from "../../src/enums/PairType.sol";
import {PairVariant} from "../../src/enums/PairVariant.sol";
import {ICurve} from "../../src/interfaces/ICurve.sol";

contract MockPair is IPair {
    function pairType() external pure returns (PairType) {
        return PairType.LAUNCH;
    }

    function pairVariant() external pure returns (PairVariant) {
        return PairVariant.ERC7007_ETH;
    }

    function token() external pure returns (address) {
        return address(0);
    }

    function nft() external pure returns (address) {
        return address(0);
    }

    function owner() external pure returns (address) {
        return address(0);
    }

    function getBuyNFTQuote(
        uint256, /* assetId */
        uint256, /* numItems */
        bool /* isPick */
    ) external pure returns (uint256 inputAmount, uint256 aigcAmount, uint256 royaltyAmount) {
        return (0, 0, 0);
    }

    function getSellNFTQuote(
        uint256, /* assetId */
        uint256 /* numItems */
    ) external pure returns (uint256 outputAmount, uint256 royaltyAmount) {
        return (0, 0);
    }

    function getPresaleQuote(
        uint256, /* assetId */
        uint256 /* numItems */
    ) external pure returns (uint256 inputAmount, uint256 aigcAmount, uint256 royaltyAmount) {
        return (0, 0, 0);
    }

    function purchasePresale(
        uint256, /* nftNum */
        uint256, /* maxExpectedTokenInput */
        address, /* nftRecipient */
        bytes32[] calldata, /* merkleProof */
        bool, /* isRouter */
        address /* routerCaller */
    ) external payable returns (uint256 presaleNum, uint256 totalAmount) {
        return (0, 0);
    }

    function swapTokenForNFTs(
        uint256, /* nftNum */
        uint256, /* maxExpectedTokenInput */
        address, /* nftRecipient */
        bool, /* isRouter */
        address /* routerCaller */
    ) external payable returns (uint256 nftNumOutput, uint256 tokenInput) {
        return (0, 0);
    }

    function swapTokenForSpecificNFTs(
        uint256[] calldata, /* targetTokenIds */
        uint256, /* minNFTNum */
        uint256, /* maxExpectedTokenInput */
        address, /* nftRecipient */
        bool, /* isRouter */
        address /* routerCaller */
    ) external payable returns (uint256 nftNumOutput, uint256 tokenInput) {
        return (0, 0);
    }

    function swapNFTsForToken(
        uint256[] calldata, /* tokenIds */
        uint256, /* minExpectedTokenOutput */
        address payable, /* tokenRecipient */
        bool, /* isRouter */
        address /* routerCaller */
    ) external pure returns (uint256 tokenOutput) {
        return 0;
    }
}
