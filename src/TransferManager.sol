// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

import {ITransferManager} from "./interfaces/ITransferManager.sol";
import {IPairFactory} from "./interfaces/IPairFactory.sol";

contract TransferManager is ITransferManager {
    address public immutable pairFactory;

    constructor(
        address _pairFactory
    ) {
        pairFactory = _pairFactory;
    }

    modifier onlyPair() {
        require(IPairFactory(pairFactory).isValidPair(msg.sender), "only Pair");
        _;
    }

    function transferERC721(address nft, address from, address to, uint256[] calldata tokenIds) external onlyPair {
        require(tokenIds.length > 0);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            IERC721(nft).transferFrom(from, to, tokenIds[i]);
        }
    }

    function transferERC20(address token, address from, address to, uint256 amount) external onlyPair {
        IERC20(token).transferFrom(from, to, amount);
    }

    function transferERC1155(
        address nft,
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external onlyPair {
        IERC1155(nft).safeBatchTransferFrom(from, to, ids, amounts, "");
    }
}
