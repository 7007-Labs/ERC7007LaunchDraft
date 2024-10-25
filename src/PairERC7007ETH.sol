// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";

import {PairType} from "./enums/PairType.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IPair} from "./interfaces/IPair.sol";
import {ICurve} from "./interfaces/ICurve.sol";
import {IRoyaltyManager} from "./interfaces/IRoyaltyManager.sol";

contract PairERC7007ETH is IPair, Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using Address for address;
    using BitMaps for BitMaps.BitMap;

    IRoyaltyManager public immutable royaltyManager;
    address public immutable factory;
    PairType pairType = PairType.LAUNCH;
    address public nft;
    address public bondingCurve;
    address private propertyChecker;
    BitMaps.BitMap _hasSaled;
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
    event FeeUpdate(uint96 fee);

    // Errors
    error TradeFeeTooLarge();
    error ZeroSwapAmount();

    constructor(IRoyaltyManager _royaltyManager) {
        royaltyManager = _royaltyManager;
        _disableInitializers();
    }

    function initialize(
        address _nft,
        address _bondingCurve,
        address _propertyChecker,
        address _owner,
        address payable _assetRecipient,
        uint96 _fee
    ) external initializer {
        __Ownable_init(_owner);
        nft = _nft;
        if (_fee > MAX_TRADE_FEE) revert TradeFeeTooLarge();
        fee = _fee;
        propertyChecker = _propertyChecker;
    }

    function swapTokenForSpecificNFTs(uint256[] calldata nftIds, uint256 maxExpectedTokenInput, address nftRecipient)
        external
        payable
        nonReentrant
        returns (uint256)
    {
        if (nftIds.length == 0) revert ZeroSwapAmount();

        // 计算价格
        uint256 price = ICurve(bondingCurve).getBuyPrice(address(this), nftIds.length);

        // 计算交易费用

        // 计算royalties

        // 检查滑点

        // 转token

        // 转nft

        // 返回要支付的总金额
    }

    function swapNFTsForToken(uint256[] calldata nftIds, uint256 minExpectedTokenOutput, address payable tokenRecipient)
        external
        nonReentrant
        returns (uint256)
    {
        if (nftIds.length == 0) revert ZeroSwapAmount();
        uint256 price = ICurve(bondingCurve).getBuyPrice(address(this), nftIds.length);
    }

    /* 敏感函数 */
    // todo: 统一的fee Manager?
    function updateFee(uint96 _fee) public {
        require(factory == msg.sender, "Only Factory");
        if (_fee > MAX_TRADE_FEE) revert TradeFeeTooLarge();
        fee = _fee;
        emit FeeUpdate(fee);
    }
}
