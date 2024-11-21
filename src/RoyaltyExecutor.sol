// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

import {IPair} from "./interfaces/IPair.sol";
import {IRoyaltyExecutor} from "./interfaces/IRoyaltyExecutor.sol";

/**
 * @title RoyaltyExecutor
 * @notice Calculates NFT royalties for trading pairs
 */
contract RoyaltyExecutor is IRoyaltyExecutor, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    /// @dev pair address => whether the pair is allowed to calc royalty
    mapping(address => bool) public pairRoyaltyAllowed;

    event PairRoyaltyStatusUpdate(address indexed pair, bool isAllowed);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the contract
     * @param _owner Address of the contract owner
     */
    function initialize(
        address _owner
    ) external initializer {
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();
    }

    /**
     * @notice Calculates royalty fee
     * @param pair Address of the trading pair
     * @param tokenId ID of the token being sold
     * @param price Sale price of the token
     * @return recipients Array of royalty recipients
     * @return amounts Array of royalty amounts
     * @return royaltyAmount
     */
    function calculateRoyalty(
        address pair,
        uint256 tokenId,
        uint256 price
    ) external view returns (address payable[] memory recipients, uint256[] memory amounts, uint256 royaltyAmount) {
        if (!pairRoyaltyAllowed[pair]) {
            return (new address payable[](0), new uint256[](0), 0);
        }

        address nft = IPair(pair).nft();

        (address recipient, uint256 amount) = _getRoyalty(nft, tokenId, price);

        if (recipient == address(0) || amount == 0) {
            return (new address payable[](0), new uint256[](0), 0);
        }

        recipients = new address payable[](1);
        amounts = new uint256[](1);
        recipients[0] = payable(recipient);
        amounts[0] = amount;
        royaltyAmount = amount;
    }

    function _getRoyalty(
        address nft,
        uint256 tokenId,
        uint256 price
    ) internal view returns (address recipient, uint256 amount) {
        try IERC2981(nft).royaltyInfo(tokenId, price) returns (address newRecipient, uint256 newAmount) {
            recipient = newRecipient;
            amount = newAmount;
        } catch {}
    }

    /**
     * @notice Enable or disable royalties for a trading pair
     * @param pair Address of the trading pair
     * @param isAllowed Whether to enable or disable royalties
     */
    function setPairRoyaltyStatus(address pair, bool isAllowed) external onlyOwner {
        pairRoyaltyAllowed[pair] = isAllowed;
        emit PairRoyaltyStatusUpdate(pair, isAllowed);
    }

    /**
     * @notice Batch enable or disable royalties for trading pairs
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
