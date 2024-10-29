// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";
import {IPair} from "./interfaces/IPair.sol";

// todo: 权限细分,分出运营权限
contract FeeManager is IFeeManager, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    uint256 internal constant MAX_BPS = 5000;
    uint256 internal constant BASIS_POINTS = 10000;
    address public immutable pairFactory;

    address public protocolFeeRecipient;

    mapping(address pair => FeeConfig) public configs;

    constructor(address _pairFactory) {
        pairFactory = _pairFactory;
        _disableInitializers();
    }

    function initialize(address _owner, address _protocolFeeRecipient) external initializer {
        __Ownable_init(_owner);
        protocolFeeRecipient = _protocolFeeRecipient;
    }

    function registerPair(address pair, FeeConfig memory config) external {
        // only pairFactory
        require(msg.sender == pairFactory);
        require(configs[pair].recipient == address(0));
        require(config.recipient != address(0));

        configs[pair] = FeeConfig({recipient: config.recipient, feeBPS: config.feeBPS, protocolBPS: config.protocolBPS});
    }

    function getPairConfig(address pair) external view returns (FeeConfig memory) {
        return configs[pair];
    }

    function calculateFees(address pair, uint256 amount)
        external
        view
        returns (address[] memory recipients, uint256[] memory amounts)
    {
        FeeConfig storage config = configs[pair];
        require(config.recipient != address(0));

        recipients = new address[](2);
        amounts = new uint256[](2);

        recipients[0] = config.recipient;
        amounts[0] = (amount * config.feeBPS) / BASIS_POINTS;

        recipients[1] = protocolFeeRecipient;
        amounts[1] = (amount * config.protocolBPS) / BASIS_POINTS;

        return (recipients, amounts);
    }

    function updatePairCreatorFeeRecipient(address pair, address newRecipient) external {
        // only the owner of pair
        require(msg.sender == IPair(pair).owner());
        FeeConfig storage config = configs[pair];
        require(config.recipient != address(0));
        require(newRecipient != address(0));

        config.recipient = newRecipient;
    }

    function updateProtocolFeeRecipient(address newProtocolFeeRecipient) external onlyOwner {
        protocolFeeRecipient = newProtocolFeeRecipient;
    }

    function updatePairFeeBPS(address pair, uint16 newFeeBPS, uint16 newProtocolBPS) external onlyOwner {
        require(newFeeBPS + newProtocolBPS <= MAX_BPS);
        FeeConfig storage config = configs[pair];
        require(config.recipient != address(0));

        config.feeBPS = newFeeBPS;
        config.protocolBPS = newProtocolBPS;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
