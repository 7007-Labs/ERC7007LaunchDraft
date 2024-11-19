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

/**
 * @title PairFactory
 * @notice Factory contract for creating and managing ERC7007-ETH trading pairs.
 */
contract PairFactory is IPairFactory, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    /// @dev Address of the beacon contract that stores the implementation logic for ERC7007-ETH pairs
    address public erc7007ETHBeacon;

    /// @dev bonding curve address => whether the curve is allowed
    mapping(address => bool) public bondingCurveAllowed;

    /// @dev router address => whether the router is allowed
    mapping(address router => bool) public isRouterAllowed;

    /// @dev address => whether the address is allowed to create pairs
    mapping(address => bool) public allowlist;

    event RouterStatusUpdate(address indexed router, bool isAllowed);
    event BondingCurveStatusUpdate(address indexed bondingCurve, bool isAllowed);
    event AllowlistStatusUpdate(address indexed addr, bool isAllowed);
    event NewPair(address indexed pair, address nft);

    error UnauthorizedCaller();
    error WrongPairType();
    error BondingCurveNotAllowed();

    modifier onlyAllowlist() {
        if (!allowlist[msg.sender]) revert UnauthorizedCaller();
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the PairFactory contract
     * @param _owner Address that will be granted ownership rights
     * @param _erc7007ETHBeacon Address of the beacon contract for ERC7007-ETH pairs
     */
    function initialize(address _owner, address _erc7007ETHBeacon) external initializer {
        __Ownable_init(_owner);
        erc7007ETHBeacon = _erc7007ETHBeacon;
    }

    /**
     * @dev Create a new ERC7007-ETH trading pair
     * @param _owner Address that will own the new pair
     * @param _nft Address of the NFT contract to be traded
     * @param _pairType Type of pair to create (must be LAUNCH type)
     * @param _propertyChecker Address of the property checker contract
     * @param params ABI encoded parameters
     * @return pair Address of the newly created pair
     * @notice Only allowlisted addresses can create pairs
     * @notice Only LAUNCH type pairs are currently supported
     */
    function createPairERC7007ETH(
        address _owner,
        address _nft,
        PairType _pairType,
        address _propertyChecker,
        bytes calldata params
    ) external payable onlyAllowlist returns (address pair) {
        if (_pairType == PairType.LAUNCH) {
            pair = _deployPair(_pairType, _nft);
            (uint256 _nftTotalSupply, IPair.SalesConfig memory _salesConfig) =
                abi.decode(params, (uint256, IPair.SalesConfig));

            if (!bondingCurveAllowed[address(_salesConfig.bondingCurve)]) revert BondingCurveNotAllowed();

            PairERC7007ETH(pair).initialize(_owner, _nft, _propertyChecker, _nftTotalSupply, _salesConfig);
            emit NewPair(pair, _nft);
        } else {
            revert WrongPairType();
        }
    }

    /**
     * @dev Deploy a new pair using CREATE2
     * @param _pairType Type of pair being deployed
     * @param _nft Address of the NFT contract
     * @return Address of the deployed pair
     */
    function _deployPair(PairType _pairType, address _nft) internal returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(_pairType, _nft));
        bytes memory initCode = abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(erc7007ETHBeacon, ""));
        return Create2.deploy(0, salt, initCode);
    }

    /**
     * @notice Update the allowlist status of a router
     * @param router Address of the router to update
     * @param isAllowed New allowlist status
     */
    function setRouterAllowed(address router, bool isAllowed) external onlyOwner {
        isRouterAllowed[router] = isAllowed;
        emit RouterStatusUpdate(router, isAllowed);
    }

    /**
     * @notice Update the allowlist status of a bonding curve
     * @param bondingCurve Address of the bonding curve to update
     * @param isAllowed New allowlist status
     */
    function setBondingCurveAllowed(address bondingCurve, bool isAllowed) external onlyOwner {
        bondingCurveAllowed[bondingCurve] = isAllowed;
        emit BondingCurveStatusUpdate(bondingCurve, isAllowed);
    }

    /**
     * @notice Update the allowlist status of an address
     * @param addr Address to update
     * @param isAllowed New allowlist status
     */
    function setAllowlistAllowed(address addr, bool isAllowed) external onlyOwner {
        allowlist[addr] = isAllowed;
        emit AllowlistStatusUpdate(addr, isAllowed);
    }

    /**
     * @dev Required by UUPS pattern
     */
    function _authorizeUpgrade(
        address
    ) internal override onlyOwner {}
}
