// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {PairType} from "./enums/PairType.sol";
import {IPair} from "./interfaces/IPair.sol";
import {ICurve} from "./interfaces/ICurve.sol";
import {ITotalSupply} from "./interfaces/ITotalSupply.sol";
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
    BitMaps.BitMap _notOwnedNFTs;
    uint256 _saleStartTokenID; //从这个id开始卖，这个id后面的都是unReveal的

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

    function swapTokenForNFTs(
        uint256 nftNum,
        uint256[] desiredTokenIds,
        uint256 maxExpectedTokenInput,
        address nftRecipient
    ) external payable nonReentrant returns (uint256) {
        if (nftNum == 0) revert ZeroSwapAmount();
        uint256 nftTotalSupply = ITotalSupply(nft).totalSupply();

        // 方案一，严格限制要先选择未开盒的
        // 1.先选择未开盒的
        uint256[] memory tokenIds = new uint256[](nftNum);
        uint256 unRevealNFTNum = Math.min(nftTotalSupply - _saleStartTokenID, nftNum);
        for (uint256 i = 0; i < unRevealNFTNum; i++) {
            tokenIds[i] = _saleStartTokenID + i;
        }
        _saleStartTokenID += unRevealNFTNum;

        // 2.选择未开盒的
        // todo: 此过程需要优化 定制bitMap来完成优化? 外部传入tokenIds ?卖的时候存储条目
        uint256 total = unRevealNFTNum;
        for (uint256 i = 0; i < nftTotalSupply; i++) {
            if (total >= nftNum) break;
            if (_notOwnedNFTs.get(i) == false) {
                tokenIds[total] = i;
                total += 1;
                // 置为已卖出
                _notOwnedNFTs.set(i);
            }
        }

        //方案二:支持选购,没法严格限制先购买未开盒的
        // 1.前端通过indexer筛选出未开盒的tokenIds,(接收到的tokenIds也可能是开盒了的)
        // 2.从 desiredTokenIds 中选出可以交易的
        // 3.如果数量还未达到nftNum,从bitmap中选

        // todo: 目前没有足够的NFT会交易失败
        require(total == nftNum, "Not enough nfts");

        // 计算价格
        uint256 price = ICurve(bondingCurve).getBuyPrice(address(this), nftNum);

        // 计算开盒的费用

        // 开盒

        // 计算tradingFee

        // 计算royalties

        // 检查滑点

        // 转token

        // 转nft

        // 返还多余的金额
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
