// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title ERC7007 Token Standard, optional updatable extension
 * Note: the ERC-165 identifier for this interface is 0x3f37dce2.
 */
interface IERC7007Updatable {
    /**
     * @dev Update the `aigcData` of `prompt`.
     */
    function update(bytes calldata prompt, bytes calldata aigcData) external;

    /**
     * @dev Emitted when `tokenId` token is updated.
     */
    event Update(uint256 indexed tokenId, bytes indexed prompt, bytes indexed aigcData);
}
