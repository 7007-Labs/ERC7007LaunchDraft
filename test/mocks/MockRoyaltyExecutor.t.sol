// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

contract MockRoyaltyExecutor {
    address public royaltyRecipient;
    uint256 public royaltyBps;
    bool enabled;

    constructor(address _royaltyRecipient, uint256 _royaltyBps) {
        royaltyRecipient = _royaltyRecipient;
        royaltyBps = _royaltyBps;
        enabled = true;
    }

    function updateRoyaltyInfo(address _royaltyRecipient, uint256 _royaltyBps) external {
        royaltyRecipient = _royaltyRecipient;
        royaltyBps = _royaltyBps;
    }

    function enable() external {
        enabled = true;
    }

    function disable() external {
        enabled = false;
    }

    function calculateRoyalty(
        address,
        uint256,
        uint256 salePrice
    ) external view returns (address payable[] memory recipients, uint256[] memory amounts, uint256 totalAmount) {
        if (!enabled) {
            return (recipients, amounts, totalAmount);
        }
        recipients = new address payable[](1);
        amounts = new uint256[](1);
        recipients[0] = payable(royaltyRecipient);
        amounts[0] = salePrice * royaltyBps / 10_000;
        totalAmount = amounts[0];
    }
}
