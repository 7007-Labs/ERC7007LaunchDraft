// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

import {IPair} from "./interfaces/IPair.sol";
import {IRoyaltyManager} from "./interfaces/IRoyaltyManager.sol";

contract RoyaltyManager is IRoyaltyManager, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    mapping(address => bool) public pairRoyaltyEnabled;

    event PairRoyaltyStatusUpdate(address indexed pair, bool isEnabled);

    function initialize(
        address _owner
    ) external initializer {
        __Ownable_init(_owner);
        __UUPSUpgradeable_init();
    }

    function calculateRoyaltyFee(
        address pair,
        uint256 tokenId,
        uint256 price
    ) external view returns (address payable[] memory, uint256[] memory) {
        if (!pairRoyaltyEnabled[pair]) {
            return (new address payable[](0), new uint256[](0));
        }

        address nft = IPair(pair).nft();
        (address recipient, uint256 amount) = royaltyInfo(nft, tokenId, price);
        address payable[] memory recipients = new address payable[](1);
        recipients[0] = payable(recipient);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        return (recipients, amounts);
    }

    function royaltyInfo(
        address nft,
        uint256 tokenId,
        uint256 price
    ) public view returns (address recipient, uint256 amount) {
        if (IERC2981(nft).supportsInterface(type(IERC2981).interfaceId)) {
            try IERC2981(nft).royaltyInfo(tokenId, price) returns (address newRecipient, uint256 newAmount) {
                recipient = newRecipient;
                amount = newAmount;
            } catch {}
        }
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}

    function setPairRoyaltyStatus(address pair, bool isEnabled) external onlyOwner {
        pairRoyaltyEnabled[pair] = isEnabled;
        emit PairRoyaltyStatusUpdate(pair, isEnabled);
    }

    function setBatchPairRoyaltyStatus(address[] calldata pairs, bool[] calldata isEnabled) external onlyOwner {
        require(pairs.length == isEnabled.length, "Input arrays must have the same length");
        for (uint256 i = 0; i < pairs.length; i++) {
            pairRoyaltyEnabled[pairs[i]] = isEnabled[i];
            emit PairRoyaltyStatusUpdate(pairs[i], isEnabled[i]);
        }
    }
}
