// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Multicall} from "@openzeppelin/contracts/utils/Multicall.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";
import {IPair} from "./interfaces/IPair.sol";

/**
 * @title FeeManager
 * @notice Manages fee configurations and calculations for pairs
 */
contract FeeManager is IFeeManager, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    /// @dev Maximum allowed fee in basis points (50%)
    uint256 private constant MAX_BPS = 5000;
    /// @dev Basis points denominator (100%)
    uint256 private constant BASIS_POINTS = 10_000;
    /// @dev Address that receives protocol fees
    address public protocolFeeRecipient;

    /// @dev pair address => fee configuration
    mapping(address => PairFeeConfig) public pairConfigs;

    error ZeroAddress();
    error FeesExceedMaximum();
    error PairAlreadyRegistered();
    error PairNotRegistered();
    error NotPairOwner();

    event PairRegistered(address indexed pair, address indexed feeRecipient, uint16 pairFeeBps, uint16 protocolFeeBps);
    event PairRecipientUpdated(address indexed pair, address indexed oldRecipient, address indexed newRecipient);
    event ProtocolRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event PairFeesUpdated(address indexed pair, uint16 pairFeeBps, uint16 protocolFeeBps);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the contract
     * @param initialOwner Address of the contract owner
     * @param initialFeeRecipient Address to receive protocol fees
     */
    function initialize(address initialOwner, address initialFeeRecipient) external initializer {
        if (initialOwner == address(0)) revert ZeroAddress();
        if (initialFeeRecipient == address(0)) revert ZeroAddress();

        __Ownable_init(initialOwner);
        protocolFeeRecipient = initialFeeRecipient;
    }

    /**
     * @notice Register a new pair with fee configuration
     * @param feeRecipient Address to receive pair fees
     * @param pairFeeBps Pair fee in basis points
     * @param protocolFeeBps Protocol fee in basis points
     */
    function registerPair(address feeRecipient, uint16 pairFeeBps, uint16 protocolFeeBps) external {
        if (feeRecipient == address(0)) revert ZeroAddress();
        if (pairFeeBps + protocolFeeBps > MAX_BPS) revert FeesExceedMaximum();

        PairFeeConfig storage config = pairConfigs[msg.sender];
        if (config.feeRecipient != address(0)) revert PairAlreadyRegistered();

        config.feeRecipient = feeRecipient;
        config.pairFeeBps = pairFeeBps;
        config.protocolFeeBps = protocolFeeBps;

        emit PairRegistered(msg.sender, feeRecipient, pairFeeBps, protocolFeeBps);
    }

    /**
     * @notice Gets the fee configuration for a pair
     * @param pair Address of the pair
     * @return config Fee configuration
     */
    function getConfig(
        address pair
    ) external view returns (PairFeeConfig memory config) {
        return pairConfigs[pair];
    }

    /**
     * @notice Calculate fees for a given amount
     * @param pair Address of the pair
     * @param amount The amount to calculate fees for
     * @return recipients Array of fee recipients
     * @return amounts Array of fee amounts
     */
    function calculateFees(
        address pair,
        uint256 amount
    ) external view returns (address payable[] memory recipients, uint256[] memory amounts, uint256 totalAmount) {
        PairFeeConfig storage config = pairConfigs[pair];
        if (config.feeRecipient == address(0)) revert PairNotRegistered();

        uint256 pairFee = (amount * config.pairFeeBps) / BASIS_POINTS;
        uint256 protocolFee = (amount * config.protocolFeeBps) / BASIS_POINTS;

        recipients = new address payable[](2);
        amounts = new uint256[](2);

        recipients[0] = payable(config.feeRecipient);
        recipients[1] = payable(protocolFeeRecipient);

        amounts[0] = pairFee;
        amounts[1] = protocolFee;
        totalAmount = pairFee + protocolFee;
    }

    /**
     * @notice Update the fee recipient for a pair
     * @param pair Address of the pair
     * @param newFeeRecipient New fee recipient address
     */
    function updatePairRecipient(address pair, address newFeeRecipient) external {
        if (msg.sender != IPair(pair).owner()) revert NotPairOwner();
        if (newFeeRecipient == address(0)) revert ZeroAddress();

        PairFeeConfig storage config = pairConfigs[pair];
        if (config.feeRecipient == address(0)) revert PairNotRegistered();

        address oldRecipient = config.feeRecipient;
        config.feeRecipient = newFeeRecipient;

        emit PairRecipientUpdated(pair, oldRecipient, newFeeRecipient);
    }

    /**
     * @notice Update the protocol fee recipient
     * @param newFeeRecipient New protocol fee recipient address
     */
    function updateProtocolRecipient(
        address newFeeRecipient
    ) external onlyOwner {
        if (newFeeRecipient == address(0)) revert ZeroAddress();

        address oldRecipient = protocolFeeRecipient;
        protocolFeeRecipient = newFeeRecipient;

        emit ProtocolRecipientUpdated(oldRecipient, newFeeRecipient);
    }

    /**
     * @notice Update fees for a pair
     * @param pair Address of the pair
     * @param pairFeeBps New pair fee in basis points
     * @param protocolFeeBps New protocol fee in basis points
     */
    function updatePairFees(address pair, uint16 pairFeeBps, uint16 protocolFeeBps) external onlyOwner {
        if (pairFeeBps + protocolFeeBps > MAX_BPS) revert FeesExceedMaximum();

        PairFeeConfig storage config = pairConfigs[pair];
        if (config.feeRecipient == address(0)) revert PairNotRegistered();

        config.pairFeeBps = pairFeeBps;
        config.protocolFeeBps = protocolFeeBps;

        emit PairFeesUpdated(pair, pairFeeBps, protocolFeeBps);
    }

    /**
     * @dev Required by UUPS pattern
     */
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyOwner {}
}
