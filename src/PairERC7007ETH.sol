// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IPair} from "./interfaces/IPair.sol";
import {IRoyaltyManager} from "./interfaces/IRoyaltyManager.sol";

contract PairERC7007ETH is IPair, Initializable, OwnableUpgradeable {
    using Address for address;

    IRoyaltyManager public immutable royaltyManager;
    address public immutable factory;
    address public immutable collection;

    address private propertyChecker;

    /**
     * @dev 50%, must <= 1 - MAX_PROTOCOL_FEE (set in LSSVMPairFactory)
     */
    uint256 internal constant MAX_TRADE_FEE = 0.5e18;

    /**
     * @notice The spread between buy and sell prices, set to be a multiplier we apply to the buy price
     * Fee is only relevant for TRADE pools. Units are in base 1e18.
     */
    uint96 public fee; //

    /**
     * @notice The address that swapped assets are sent to.
     * For TRADE pools, assets are always sent to the pool, so this is used to track trade fee.
     * If set to address(0), will default to owner() for NFT and TOKEN pools.
     */
    address payable internal assetRecipient;

    // Events
    event SwapNFTInPair(uint256 amountOut, uint256[] ids);
    event SwapNFTInPair(uint256 amountOut, uint256 numNFTs);
    event SwapNFTOutPair(uint256 amountIn, uint256[] ids);
    event SwapNFTOutPair(uint256 amountIn, uint256 numNFTs);
    event AssetRecipientChange(address indexed a);

    // Errors
    constructor(IRoyaltyManager _royaltyManager) {
        royaltyManager = _royaltyManager;
    }

    function initialize(address _owner, address payable _assetRecipient, address _propertyChecker)
        external
        initializer
    {
        __Ownable_init(_owner);
        propertyChecker = _propertyChecker;
    }
}
