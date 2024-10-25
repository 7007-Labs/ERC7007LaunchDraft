// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PairType} from "../enums/PairType.sol";

interface IPair {
    function getAssetRecipient() external returns (address);

    function changeAssetRecipient(address payable newRecipient) external;

    function pairType() external view returns (PairType);

    function token() external view returns (address _token);

    function nft() external view returns (address);

    function getBuyNFTQuote(uint256 assetId, uint256 numItems)
        external
        view
        returns (uint256 inputAmount, uint256 royaltyAmount);

    function getSellNFTQuote(uint256 assetId, uint256 numItems)
        external
        view
        returns (uint256 outputAmount, uint256 royaltyAmount);

    function withdrawERC20(address token, uint256 amount) external;

    function withdrawERC721(address nft, uint256[] calldata nftIds) external;
}
