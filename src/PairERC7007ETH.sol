// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {PairType} from "./enums/PairType.sol";
import {IPair} from "./interfaces/IPair.sol";
import {ICurve} from "./interfaces/ICurve.sol";
import {ITotalSupply} from "./interfaces/ITotalSupply.sol";
import {IRoyaltyManager} from "./interfaces/IRoyaltyManager.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";
import {IAIOracleManager} from "./interfaces/IAIOracleManager.sol";

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
            uint256 tokenId = desiredTokenIds[i];
            // 过滤掉未开盒的
            if (tokenId < _saleStartTokenID) {
                continue;
            }
            try IERC721(nft).transferFrom(address(this), nftRecipient, tokenId) {
                availableTokenIds[availableTokenNum] = desiredTokenIds[i];
                i++;
                _notOwnedNFTs.set(tokenId);
            } catch {}
        }

        // 处理nftNum, 先购买没有开的，再购买开了的
        uint256 unRevealedNum = Math.min(nftNum, _nftTotalSupply - _saleStartTokenID);
        uint256[] memory unRevealedTokenIds = new uint256[](unRevealedNum);
        uint256[] memory tokenIds = new uint256[](nftNum);
        uint256 actualNum = unRevealedNum;
        for (uint256 i = 0; i < unRevealedNum; i++) {
            tokenIds[i] = _saleStartTokenID + i;
        }

        for (uint256 i = 0; i < _nftTotalSupply; i++) {
            if (actualNum >= nftNum) break;
            if (_notOwnedNFTs.get(i)) continue;
            tokenIds[actualNum] = i;
            actualNum += 1;
        }

        // 计算开盒的费用
        uint256 unRevealFee = IAIOracleManager(nft).estimateFee(unRevealedNum);

        // 开盒
        IAIOracleManager(nft).unReveal{value: unRevealFee}(unRevealedTokenIds);

        // 计算价格
        uint256 amount = ICurve(bondingCurve).getBuyPrice(address(this), actualNum + availableTokenNum);

        // 计算Fee
        IFeeManager(feeManager).calculateFees(address(this), amount);

        // 计算royalties
        IRoyaltyManager(royaltyManager).calculateRoyaltyFee(address(this), tokenIds, amount);

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
