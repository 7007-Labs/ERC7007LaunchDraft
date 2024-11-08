// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title IFeeManager
 * @notice Interface for managing fee configurations and calculations for trading pairs
 */
interface IFeeManager {
    /// @notice Fee configuration for a pair
    struct PairFeeConfig {
        address feeRecipient; // 160 bits
        uint16 pairFeeBps; // 16 bits
        uint16 protocolFeeBps; // 16 bits
    }

    function registerPair(address feeRecipient, uint16 pairFeeBps, uint16 protocolFeeBps) external;

    function getConfig(
        address pair
    ) external view returns (PairFeeConfig memory config);

    function calculateFees(
        address pair,
        uint256 amount
    ) external view returns (address payable[] memory recipients, uint256[] memory amounts);
}
