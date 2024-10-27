// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

// todo: 权限细分
contract FeeManager is Initializable, OwnableUpgradeable, UUPSUpgradeable, PausableUpgradeable {
    uint256 internal constant MAX_BPS = 5000;

    struct FeeConfig {
        uint64 protocolBPS; //给协议的比例
        uint64 creatorBPS; //给创建者的比例
            // uint64 roylatyBPS; //限制的royalty，0表示不启用    // 后续可以添加其它的
    }
    address public protocolFeeRecipient;

    mapping(address pair => address) public pairFeeRecipients;

    mapping(address pair => FeeConfig) public configs;

    function initialize(address _owner, address _protocolFeeRecipient) external initializer {
        __Ownable_init(_owner);
        __Pausable_init();
        protocolFeeRecipient = _protocolFeeRecipient;
    }

    function initPair(address pair, uint64 protocolBPS, uint64 creatorBPS, )

    function calcFees(address pair, uint256 amount) view
        returns (address[] memory recipients, uint256[] memory amounts, uint256 total)
    {
        //
    }

    function updatePairCreatorFeeRecipient(address pair, address newRecipient) {
        require(msg.sender == IOwnable(pair).owner());
        pairFeeRecipients[pair] = newRecipient;
    }

    function updateProtocolFeeRecipient(address newProtocolFeeRecipient) onlyOwner {
        protocolFeeRecipient = newProtocolFeeRecipient;
    }

    function updatePairFeeConfig(FeeConfig calldata config) onlyOwner {
        // todo: 权限拆分

    }
    /*
    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }
    */
}
