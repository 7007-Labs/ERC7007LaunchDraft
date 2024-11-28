// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

contract MockFeeManager {
    address public feeRecipient;
    uint256 public feeBps;
    address public protocolFeeRecipient;
    uint256 public protocolFeeBps;

    constructor(address _feeRecipient, uint256 _feeBps, address _protocolFeeRecipient, uint256 _protocolFeeBps) {
        feeRecipient = _feeRecipient;
        feeBps = _feeBps;
        protocolFeeRecipient = _protocolFeeRecipient;
        protocolFeeBps = _protocolFeeBps;
    }

    function updateFeeInfo(address _feeRecipient, uint256 _feeBps) external {
        feeRecipient = _feeRecipient;
        feeBps = _feeBps;
    }

    function updateProtocolFeeInfo(address _protocolFeeRecipient, uint256 _protocolFeeBps) external {
        protocolFeeRecipient = _protocolFeeRecipient;
        protocolFeeBps = _protocolFeeBps;
    }

    function calculateFees(
        address,
        uint256 price
    ) external view returns (address payable[] memory recipients, uint256[] memory amounts, uint256 totalAmount) {
        recipients = new address payable[](2);
        amounts = new uint256[](2);
        recipients[0] = payable(feeRecipient);
        recipients[1] = payable(protocolFeeRecipient);
        amounts[0] = price * feeBps / 10_000;
        amounts[1] = price * protocolFeeBps / 10_000;
        totalAmount = amounts[0] + amounts[1];
    }

    function registerPair(address owner, uint16 _feeBps, uint16 _protocolFeeBps) external {}
}
