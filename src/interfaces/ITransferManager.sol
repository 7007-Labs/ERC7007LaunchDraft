// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface ITransferManager {
    function transferERC721(address nft, address from, address to, uint256[] calldata tokenIds) external;
    function transferERC20(address token, address from, address to, uint256 amount) external;
    function transferERC1155(
        address nft,
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external;
}
