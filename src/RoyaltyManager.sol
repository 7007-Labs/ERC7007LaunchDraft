// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

import {IPair} from "./interfaces/IPair.sol";
import {IRoyaltyManager} from "./interfaces/IRoyaltyManager.sol";

/**
 * @title RoyaltyManager
 * @dev Manages NFT royalties for trading pairs
 */
contract RoyaltyManager is IRoyaltyManager, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    mapping(address => bool) public pairRoyaltyAllowed;

    event PairRoyaltyStatusUpdate(address indexed pair, bool isAllowed);

    /**
     * @dev Initialize the contract
     * @param _owner Address of the contract owner
     */
    function initialize(
        address _owner
    ) external initializer {
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();
    }

    /**
     * @dev Calculate royalty fee for a token sale
     * @param pair Address of the trading pair
     * @param tokenId ID of the token being sold
     * @param price Sale price of the token
     * @return recipients Array of royalty recipients
     * @return amounts Array of royalty amounts
     */
    function calculateRoyalty(
        address pair,
        uint256 tokenId,
        uint256 price
    ) external view returns (address payable[] memory recipients, uint256[] memory amounts, uint256 royaltyAmount) {
        // If royalties are not enabled for this pair, return empty arrays (zero royalty)
        if (!pairRoyaltyAllowed[pair]) {
            return (new address payable[](0), new uint256[](0), 0);
        }

        address nft = IPair(pair).nft();

        // Calculate royalty
        (address recipient, uint256 amount) = _getRoyalty(nft, tokenId, price);

        // If no valid royalty, return empty arrays
        if (recipient == address(0) || amount == 0) {
            return (new address payable[](0), new uint256[](0), 0);
        }

        // Return royalty information
        recipients = new address payable[](1);
        amounts = new uint256[](1);
        recipients[0] = payable(recipient);
        amounts[0] = amount;
        royaltyAmount = amount;
    }

    /**
     * @dev Internal function to get royalty
     */
    function _getRoyalty(
        address nft,
        uint256 tokenId,
        uint256 price
    ) internal view returns (address recipient, uint256 amount) {
        if (IERC2981(nft).supportsInterface(type(IERC2981).interfaceId)) {
            try IERC2981(nft).royaltyInfo(tokenId, price) returns (address newRecipient, uint256 newAmount) {
                recipient = newRecipient;
                amount = newAmount;
            } catch {
                // If royalty calculation fails, return zero royalty
                recipient = address(0);
                amount = 0;
            }
        }
    }

    /**
     * @dev Enable or disable royalties for a trading pair
     * @param pair Address of the trading pair
     * @param isAllowed Whether to enable or disable royalties
     */
    function setPairRoyaltyStatus(address pair, bool isAllowed) external onlyOwner {
        pairRoyaltyAllowed[pair] = isAllowed;
        emit PairRoyaltyStatusUpdate(pair, isAllowed);
    }

    /**
     * @dev Batch enable or disable royalties for trading pairs
     * @param pairs Array of pair addresses
     * @param isAllowed Array of enable/disable flags
     */
    function setBatchPairRoyaltyStatus(address[] calldata pairs, bool[] calldata isAllowed) external onlyOwner {
        for (uint256 i = 0; i < pairs.length; i++) {
            pairRoyaltyAllowed[pairs[i]] = isAllowed[i];
            emit PairRoyaltyStatusUpdate(pairs[i], isAllowed[i]);
        }
    }

    /**
     * @dev Required by UUPS pattern
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
