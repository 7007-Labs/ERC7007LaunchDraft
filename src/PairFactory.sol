// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IBeacon} from "@openzeppelin/contracts/proxy/beacon/IBeacon.sol";
import {PairType} from "./enums/PairType.sol";
import {IPairFactory} from "./interfaces/IPairFactory.sol";
import {IPair} from "./interfaces/IPair.sol";
import {ICurve} from "./interfaces/ICurve.sol";
import {IORAOracleDelegateCaller} from "./interfaces/IORAOracleDelegateCaller.sol";
import {PairERC7007ETH} from "./PairERC7007ETH.sol";

/**
 * @title PairFactory
 * @notice Factory contract for creating and managing ERC7007-ETH trading pairs.
 */
contract PairFactory is IPairFactory, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    /// @dev Address of the ORAOracleDelegateCaller contract that delegates calls to the oracle
    IORAOracleDelegateCaller public immutable oraOracleDelegateCaller;

    /// @dev Stored code of type(BeaconProxy).creationCode
    bytes internal constant beaconProxyBytecode =
        hex"60a06040526040516105c53803806105c583398101604081905261002291610387565b61002c828261003e565b506001600160a01b0316608052610484565b610047826100fe565b6040516001600160a01b038316907f1cf3b03a6cf19fa2baba4df148e9dcabedea7f8a5c07840e207e5c089be95d3e90600090a28051156100f2576100ed826001600160a01b0316635c60da1b6040518163ffffffff1660e01b8152600401602060405180830381865afa1580156100c3573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906100e7919061044d565b82610211565b505050565b6100fa610288565b5050565b806001600160a01b03163b60000361013957604051631933b43b60e21b81526001600160a01b03821660048201526024015b60405180910390fd5b807fa3f0ad74e5423aebfd80d3ef4346578335a9a72aeaee59ff6cb3582b35133d5080546001600160a01b0319166001600160a01b0392831617905560408051635c60da1b60e01b81529051600092841691635c60da1b9160048083019260209291908290030181865afa1580156101b5573d6000803e3d6000fd5b505050506040513d601f19601f820116820180604052508101906101d9919061044d565b9050806001600160a01b03163b6000036100fa57604051634c9c8ce360e01b81526001600160a01b0382166004820152602401610130565b6060600080846001600160a01b03168460405161022e9190610468565b600060405180830381855af49150503d8060008114610269576040519150601f19603f3d011682016040523d82523d6000602084013e61026e565b606091505b50909250905061027f8583836102a9565b95945050505050565b34156102a75760405163b398979f60e01b815260040160405180910390fd5b565b6060826102be576102b982610308565b610301565b81511580156102d557506001600160a01b0384163b155b156102fe57604051639996b31560e01b81526001600160a01b0385166004820152602401610130565b50805b9392505050565b8051156103185780518082602001fd5b60405163d6bda27560e01b815260040160405180910390fd5b80516001600160a01b038116811461034857600080fd5b919050565b634e487b7160e01b600052604160045260246000fd5b60005b8381101561037e578181015183820152602001610366565b50506000910152565b6000806040838503121561039a57600080fd5b6103a383610331565b60208401519092506001600160401b038111156103bf57600080fd5b8301601f810185136103d057600080fd5b80516001600160401b038111156103e9576103e961034d565b604051601f8201601f19908116603f011681016001600160401b03811182821017156104175761041761034d565b60405281815282820160200187101561042f57600080fd5b610440826020830160208601610363565b8093505050509250929050565b60006020828403121561045f57600080fd5b61030182610331565b6000825161047a818460208701610363565b9190910192915050565b60805161012761049e6000396000601e01526101276000f3fe6080604052600a600c565b005b60186014601a565b60a0565b565b60007f00000000000000000000000000000000000000000000000000000000000000006001600160a01b0316635c60da1b6040518163ffffffff1660e01b8152600401602060405180830381865afa1580156079573d6000803e3d6000fd5b505050506040513d601f19601f82011682018060405250810190609b919060c3565b905090565b3660008037600080366000845af43d6000803e80801560be573d6000f35b3d6000fd5b60006020828403121560d457600080fd5b81516001600160a01b038116811460ea57600080fd5b939250505056fea2646970667358221220c3e10a6990c8f9a67d261cef223ce1e8dcd6ec99c6d7890a8ad367d1472a2a8a64736f6c634300081c0033";

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
    constructor(
        IORAOracleDelegateCaller _oraOracleDelegateCaller
    ) {
        oraOracleDelegateCaller = _oraOracleDelegateCaller;
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

            oraOracleDelegateCaller.addToAllowlist(_nft);

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
        bytes memory initCode = abi.encodePacked(beaconProxyBytecode, abi.encode(erc7007ETHBeacon, ""));
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
