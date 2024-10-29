// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {PairType} from "./enums/PairType.sol";
import {IPairFactory} from "./interfaces/IPairFactory.sol";
import {ICurve} from "./interfaces/ICurve.sol";
import {PairERC7007ETH} from "./PairERC7007ETH.sol";

contract PairFactory is IPairFactory, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    mapping(ICurve => bool) public bondingCurveAllowed;
    mapping(address nft => address) public getLaunchPair;

    address public erc7007ETHBeacon;

    function initialize(address _owner, address _erc7007ETHBeacon) external initializer {
        __Ownable_init(_owner);
        erc7007ETHBeacon = _erc7007ETHBeacon;
    }

    function createPairERC7007ETH(
        address _nft,
        ICurve _bondingCurve,
        PairType _pairType,
        address _propertyChecker,
        address payable _assetRecipient,
        bytes calldata _data // 不同pairType可能会用到
    ) external payable returns (address pair) {
        require(bondingCurveAllowed[_bondingCurve] == true);
        if (_pairType == PairType.LAUNCH) {
            require(getLaunchPair[_nft] == address(0));
            // BeaconProxy proxy = new BeaconProxy(erc7007ETHBeacon, abi.encodeCall(PairERC7007ETH.initialize, ()));
        }
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}
}
