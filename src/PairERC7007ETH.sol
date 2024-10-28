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
import {IFeeManager} from "./interfaces/IFeeManager.sol";

// todo: 优化，将一些变量放到code里或者一些用到的参数放到calldata里
contract PairERC7007ETH is IPair, Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using Address for address;
    using BitMaps for BitMaps.BitMap;

    IRoyaltyManager public immutable royaltyManager;
    IFeeManager public immutable feeManager;
    address public immutable factory;
    address public nft;
    address public bondingCurve;
    address public propertyChecker;
    BitMaps.BitMap private _notOwnedNFTs; // todo: 实现优化
    uint256 private _saleStartTokenID; //从这个id开始卖，这个id后面的都是unReveal的
    uint256 private _nftTotalSupply;
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
    error TradeFeeTooLarge();
    error ZeroSwapAmount();

    constructor(IRoyaltyManager _royaltyManager, IFeeManager _feeManager) {
        royaltyManager = _royaltyManager;
        feeManager = _feeManager;
        _disableInitializers();
    }

    function initialize(
        address _owner,
        address _nft,
        address _bondingCurve,
        PairType _pairType,
        address _propertyChecker,
        address payable _assetRecipient
    ) external initializer {
        __Ownable_init(_owner);
        nft = _nft;
        propertyChecker = _propertyChecker;
        _nftTotalSupply = ITotalSupply(nft).totalSupply();
    }

    function swapTokenForNFTs(
        uint256 nftNum,
        uint256[] desiredTokenIds,
        uint256 maxExpectedTokenInput,
        address nftRecipient
    ) external payable nonReentrant returns (uint256) {
        if ((nftNum + desiredTokenIds.length) == 0) revert ZeroSwapAmount();

        //先处理选购的，选购只支持购买已经开盒了的,选购有可能购买失败,购买失败时忽略
        uint256[] memory availableTokenIds = new uint256[]();
        uint256 availableTokenNum = 0;
        for (uint256 i = 0; i < desiredTokenIds.length; i++) {
            //todo: 将nft转给nftRecipient, 允许失败
        }

        // todo: 选购时没有则跳过

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

        // 将用户的NFT(ERC20)转移进来
        //1.方案一，使用类似于uniswap v3 的callback, callback(nftIds, ethAmount, data)
        // 调用方在callback里将nft转移进来

        //2.方案二，用户将token授权给这个合约，当前合约转用户资产转移过来

        //3.方案三，用户将token授权给特定合约(例如router)，让特定合约将用户资产转到当前合约
        // 这种需要信任当前合约
    }

    // address(0) 代表eth
    function token() pure returns (address) {}

    function pairType() pure returns (PairType) {
        return PairType.LAUNCH;
    }

    function pairVariant() pure returns (PairVariant) {
        return PairVariant.ERC7007_ETH;
    }
}
