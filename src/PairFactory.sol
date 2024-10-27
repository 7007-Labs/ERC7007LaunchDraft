// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {IPairFactory} from "./interfaces/IPairFactory.sol";
import {PairERC7007ETH} from "./PairERC7007ETH.sol";

contract PairFactory is IPairFactory, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    address public erc7007ETHBeacon;
    address feeRecipient;

    mapping(address nft => address) public getPair;

    event FeeRecipientUpdate(address indexed recipientAddress);

    function initialize(address _owner, address _erc7007ETHBeacon) external initializer {
        __Ownable_init(_owner);
        erc7007ETHBeacon = _erc7007ETHBeacon;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    // 调用方: Launch
    // 调用权限: 限制只有Launch能调用
    function createPairERC7007ETH(string memory name, string memory symbol, address _owner)
        external
        payable
        returns (address)
    {
        // BeaconProxy proxy = new BeaconProxy(erc7007ETHBeacon, abi.encodeCall(PairERC7007ETH.initialize, ()));
        // return address(proxy);
        return address(0);
    }

    /**
     * Admin functions
     */
    //

    // pair中收的交易费用会发到这里，从这里提取
    function withdrawETHFees() external onlyOwner {}

    function withdrawERC20Fees() external onlyOwner {}
}
