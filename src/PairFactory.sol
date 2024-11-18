// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {PairType} from "./enums/PairType.sol";
import {IPairFactory} from "./interfaces/IPairFactory.sol";
import {IPair} from "./interfaces/IPair.sol";
import {ICurve} from "./interfaces/ICurve.sol";
import {PairERC7007ETH} from "./PairERC7007ETH.sol";

contract PairFactory is IPairFactory, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    mapping(address => bool) public bondingCurveAllowed;
    mapping(address router => bool) public isRouterAllowed;
    mapping(address => bool) public allowlist;

    address public erc7007ETHBeacon;

    event RouterStatusUpdate(address indexed router, bool isAllowed);
    event BondingCurveStatusUpdate(address indexed bondingCurve, bool isAllowed);
    event AllowlistStatusUpdate(address indexed addr, bool isAllowed);
    event NewPair(address indexed pair, address nft);

    error UnauthorizedCaller();
    error WrongPairType();
    error BondingCurveNotAllowed();

    function initialize(address _owner, address _erc7007ETHBeacon) external initializer {
        __Ownable_init(_owner);
        erc7007ETHBeacon = _erc7007ETHBeacon;
    }

    modifier onlyAllowlist() {
        if (!allowlist[msg.sender]) revert UnauthorizedCaller();
        _;
    }

    function createPairERC7007ETH(
        address _owner,
        address _nft,
        PairType _pairType,
        address _propertyChecker,
        bytes calldata params
    ) external payable onlyAllowlist returns (address pair) {
        if (_pairType == PairType.LAUNCH) {
            pair = _deployPair(_pairType, _nft);
            (uint256 _nftTotalSupply, PairERC7007ETH.SalesConfig memory _salesConfig) =
                abi.decode(params, (uint256, PairERC7007ETH.SalesConfig));

            if (!bondingCurveAllowed[address(_salesConfig.bondingCurve)]) revert BondingCurveNotAllowed();

            PairERC7007ETH(pair).initialize(_owner, _nft, _propertyChecker, _nftTotalSupply, _salesConfig);
            emit NewPair(pair, _nft);
        } else {
            revert WrongPairType();
        }
    }

    function _deployPair(PairType _pairType, address _nft) internal returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(_pairType, _nft));
        bytes memory initCode = abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(erc7007ETHBeacon, ""));
        return Create2.deploy(0, salt, initCode);
    }

    function setRouterAllowed(address router, bool isAllowed) external onlyOwner {
        isRouterAllowed[router] = isAllowed;
        emit RouterStatusUpdate(router, isAllowed);
    }

    function setBondingCurveAllowed(address bondingCurve, bool isAllowed) external onlyOwner {
        bondingCurveAllowed[bondingCurve] = isAllowed;
        emit BondingCurveStatusUpdate(bondingCurve, isAllowed);
    }

    function setAllowlistAllowed(address addr, bool isAllowed) external onlyOwner {
        allowlist[addr] = isAllowed;
        emit AllowlistStatusUpdate(addr, isAllowed);
    }

    function _authorizeUpgrade(
        address
    ) internal override onlyOwner {}
}
