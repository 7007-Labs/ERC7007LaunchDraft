// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/**
 * @title IFeeManager
 * @notice Interface for managing fee configurations and calculations for trading pairs
 */
interface IFeeManager {
    struct FeeConfig {
        address recipient;
        uint16 feeBPS;
        uint16 protocolBPS;
    }

    function register(address recipient, uint16 feeBPS, uint16 protocolBPS) external;

    function getPairConfig(
        address pair
    ) external view returns (FeeConfig memory);

    function calculateFees(
        address pair,
        uint256 amount
    ) external view returns (address payable[] memory recipients, uint256[] memory amounts);
}
