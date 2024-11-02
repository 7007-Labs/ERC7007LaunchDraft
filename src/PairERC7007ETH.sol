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
import {PairVariant} from "./enums/PairVariant.sol";
import {IPair} from "./interfaces/IPair.sol";
import {ICurve} from "./interfaces/ICurve.sol";
import {ITotalSupply} from "./interfaces/ITotalSupply.sol";
import {IRoyaltyManager} from "./interfaces/IRoyaltyManager.sol";
import {IFeeManager} from "./interfaces/IFeeManager.sol";

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
    uint256 private nftTotalSupply;

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
        PairType _pairType,
        address _bondingCurve,
        address _propertyChecker,
        address payable _assetRecipient,
        uint256 _nftTotalSupply
    ) external initializer {
        __Ownable_init(_owner);
        nft = _nft;
        bondingCurve = _bondingCurve;
        propertyChecker = _propertyChecker;
        require(_nftTotalSupply > 0);
        nftTotalSupply = _nftTotalSupply;
    }

    function swapTokenForNFTs(
        uint256 nftNum,
        uint256[] calldata desiredTokenIds,
        uint256 maxExpectedTokenInput,
        address nftRecipient
    ) external payable nonReentrant returns (uint256) {
        if ((nftNum + desiredTokenIds.length) == 0) revert ZeroSwapAmount();

        //先处理选购的，选购只支持购买已经开盒了的,选购有可能购买失败,购买失败时忽略
        /*
        uint256[] memory availableTokenIds = new uint256[]();
        uint256 availableTokenNum = 0;
        for (uint256 i = 0; i < desiredTokenIds.length; i++) {
            //todo: 将nft转给nftRecipient, 允许失败
            uint256 tokenId = desiredTokenIds[i];
            // 过滤掉未开盒的
            if (tokenId < _saleStartTokenID) {
                continue;
            }
            // ownerOf
            try IERC721(nft).transferFrom(address(this), nftRecipient, tokenId) {
                availableTokenIds[availableTokenNum] = desiredTokenIds[i];
                i++;
                _notOwnedNFTs.set(tokenId);
            } catch {}
            // bool success, bytes result = address(nft).call(xxxx)
            // if (sucess) {

            // }
        }

        // 处理nftNum, 先购买没有开的，再购买开了的
        uint256 unRevealedNum = Math.min(nftNum, _nftTotalSupply - _saleStartTokenID);
        uint256[] memory unRevealedTokenIds = new uint256[](unRevealedNum);
        uint256[] memory tokenIds = new uint256[](nftNum);
        uint256 actualNum = unRevealedNum;
        for (uint256 i = 0; i < unRevealedNum; i++) {
            tokenIds[i] = _saleStartTokenID + i;
        }

        // uint256 startPoint = ublock.timestamp % _nftTotalSupply;
        for (uint256 i = 0; i < _nftTotalSupply; i++) {
            if (actualNum >= nftNum) break;
            // uint256 tokenId =
            // todo:
            if (_notOwnedNFTs.get(i)) continue;
            tokenIds[actualNum] = i;
            actualNum += 1;
        }

        // 计算开图的费用
        // if (unRevealedNum) {
        //     uint256 unRevealFee = IAIOracleManager(nft).estimateFee(unRevealedNum);

        //     // 开图
        //     IAIOracleManager(nft).unReveal{value: unRevealFee}(unRevealedTokenIds);
        // }

        // 计算价格
        uint256 amount = ICurve(bondingCurve).getBuyPrice(address(this), actualNum + availableTokenNum);

        // 计算Fee
        IFeeManager(feeManager).calculateFees(address(this), amount);
        uint256 totalFee = 0;

        // 计算royalties

        IRoyaltyManager(royaltyManager).calculateRoyaltyFee(address(this), tokenIds, amount);
        // amount / (1 - x) * x

        // 检查滑点

        // 转token, eth ERC20

        // 转nft

        // 返还多余的金额
        */
        return 0;
    }

    function swapNFTsForToken(
        uint256[] calldata nftIds,
        uint256 minExpectedTokenOutput,
        address payable tokenRecipient
    ) external nonReentrant returns (uint256) {
        if (nftIds.length == 0) revert ZeroSwapAmount();
        uint256 price = ICurve(bondingCurve).getBuyPrice(address(this), nftIds.length);

        // 将用户的NFT(ERC20)转移进来
        //1.方案一，使用类似于uniswap v3 的callback, callback(nftIds, ethAmount, data)
        // 调用方在callback里将nft转移进来
        // 调用结束后做检查, nftIds, callBackAddress,

        //
        // Launch(router)

        //2.方案二，用户将token授权给这个合约，当前合约转用户资产转移过来

        //3.方案三，用户将token授权给特定合约(例如router)，让特定合约将用户资产转到当前合约
        // 这种需要信任当前合约
        //launch: pairTransforNFT()
        // nft Transfer
    }

    function getBuyNFTQuote(
        uint256 assetId,
        uint256 numItems
    ) external view returns (uint256 inputAmount, uint256 royaltyAmount) {
        return (0, 0);
    }

    function getSellNFTQuote(
        uint256 assetId,
        uint256 numItems
    ) external view returns (uint256 outputAmount, uint256 royaltyAmount) {
        return (0, 0);
    }

    function getAssetRecipient() public returns (address) {
        return address(this);
    }

    function changeAssetRecipient(
        address payable
    ) external {
        revert();
    }

    function owner() public view override(IPair, OwnableUpgradeable) returns (address) {
        return OwnableUpgradeable.owner();
    }
    // address(0) 代表eth

    function token() external pure returns (address) {
        return address(0);
    }

    function pairType() external pure returns (PairType) {
        return PairType.LAUNCH;
    }

    function pairVariant() external pure returns (PairVariant) {
        return PairVariant.ERC7007_ETH;
    }
}
