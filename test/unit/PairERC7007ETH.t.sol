// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {PairType} from "../../src/enums/PairType.sol";
import {PairERC7007ETH} from "../../src/PairERC7007ETH.sol";
import {PairFactory} from "../../src/PairFactory.sol";
import {ICurve} from "../../src/interfaces/ICurve.sol";
import {IRoyaltyExecutor} from "../../src/interfaces/IRoyaltyExecutor.sol";
import {IFeeManager} from "../../src/interfaces/IFeeManager.sol";
import {IPair} from "../../src/interfaces/IPair.sol";

import {MockORAERC7007} from "../mocks/MockORAERC7007.t.sol";
import {MockCurve} from "../mocks/MockCurve.t.sol";
import {MockRoyaltyExecutor} from "../mocks/MockRoyaltyExecutor.t.sol";
import {MockFeeManager} from "../mocks/MockFeeManager.t.sol";

contract MockFactory {
    mapping(address => bool) public isRouterAllowed;

    function updateRouterStatus(address router, bool status) external {
        isRouterAllowed[router] = status;
    }
}

contract PairERC7007ETHTest is Test {
    PairERC7007ETH public pair;
    MockORAERC7007 public nft;
    MockCurve public curve;
    MockRoyaltyExecutor public royaltyExecutor;
    MockFeeManager public feeManager;
    MockFactory public factory;
    address owner = makeAddr("owner");
    address user = makeAddr("user");
    address oraOracleDelegateCaller = makeAddr("oraOracleDelegateCaller");
    address router = makeAddr("router");
    address protocolFeeRecipient = makeAddr("protocolFeeRecipient");
    uint256 pairFeeBps = 100; // 1%
    uint256 protocolFeeBps = 100; // 1%
    address pairFeeRecipient = makeAddr("pairFeeRecipient");
    uint256 nftTotalSupply = 7007;
    address nftRoyaltyRecipient = makeAddr("nftRoyaltyRecipient");
    uint256 nftRoyaltyBps = 500; // 5%
    uint256 revealFeePerNFT = 10_000;
    uint256 bondingCurveFixedPrice = 100_000;
    uint256 presalePrice = 100_000;

    function setUp() public {
        nft = new MockORAERC7007("Test NFT", "TST", revealFeePerNFT);
        curve = new MockCurve(bondingCurveFixedPrice);
        royaltyExecutor = new MockRoyaltyExecutor(nftRoyaltyRecipient, nftRoyaltyBps);
        feeManager = new MockFeeManager(pairFeeRecipient, pairFeeBps, protocolFeeRecipient, protocolFeeBps);
        factory = new MockFactory();

        PairERC7007ETH pairImpl =
            new PairERC7007ETH(address(factory), address(royaltyExecutor), address(feeManager), oraOracleDelegateCaller);
        UpgradeableBeacon pairBeacon = new UpgradeableBeacon(address(pairImpl), owner);

        address _pair = _deployPair(PairType.LAUNCH, address(nft), address(pairBeacon));
        pair = PairERC7007ETH(_pair);
        nft.batchMint(address(pair), 0, nftTotalSupply);

        factory.updateRouterStatus(router, true);
    }

    function _initPairWithDefaultConfig() internal {
        IPair.SalesConfig memory config = IPair.SalesConfig({
            presaleStart: 0,
            presaleEnd: 0,
            publicSaleStart: 0,
            presalePrice: 0,
            presaleMerkleRoot: bytes32(0),
            maxPresalePurchasePerAddress: 0,
            presaleMaxNum: 0,
            bondingCurve: curve
        });

        pair.initialize(owner, address(nft), address(0), nftTotalSupply, config);
    }

    function _initPairWithPresale(
        bytes32 presaleMerkleRoot
    ) internal {
        IPair.SalesConfig memory config = IPair.SalesConfig({
            presaleStart: uint64(block.timestamp + 1 days),
            presaleEnd: uint64(block.timestamp + 2 days),
            publicSaleStart: uint64(block.timestamp + 2 days),
            presalePrice: uint96(presalePrice),
            presaleMerkleRoot: presaleMerkleRoot,
            maxPresalePurchasePerAddress: 1,
            presaleMaxNum: 10,
            bondingCurve: curve
        });

        pair.initialize(owner, address(nft), address(0), nftTotalSupply, config);
    }

    function _deployPair(PairType _pairType, address _nft, address erc7007ETHBeacon) internal returns (address) {
        bytes32 salt = keccak256(abi.encodePacked(_pairType, _nft));
        bytes memory initCode = abi.encodePacked(type(BeaconProxy).creationCode, abi.encode(erc7007ETHBeacon, ""));
        return Create2.deploy(0, salt, initCode);
    }

    function test_PurchasePresale() public {
        _initPairWithPresale(bytes32(0));

        vm.warp(block.timestamp + 1 days + 1);

        uint256 amountBefore = 1 ether;
        vm.deal(router, amountBefore);
        vm.prank(router);

        (uint256 nftNum, uint256 amount) = pair.purchasePresale{value: 1 ether}(
            1,
            1 ether,
            user, // nftRecipient
            new bytes32[](0), // merkleProof
            true, // isRouter
            user // routerCaller
        );

        uint256 revealFee = revealFeePerNFT;
        uint256 price = bondingCurveFixedPrice;
        uint256 roaylty = price * 500 / 10_000;
        uint256 pairFee = price * 100 / 10_000;
        uint256 protocolFee = price * 100 / 10_000;

        assertEq(amount, revealFee + price + pairFee + protocolFee + roaylty, "cost is incorrect");

        uint256 amountAfter = router.balance;
        assertEq(amountBefore, amountAfter + amount, "user balance is incorrect");
        assertEq(nftNum, 1);
        assertEq(IERC721(nft).ownerOf(0), user);
        assertEq(address(pair).balance, price, "pair balance is incorrect");
        assertEq(pairFeeRecipient.balance, pairFee);
        assertEq(protocolFeeRecipient.balance, protocolFee);
    }

    function test_PruchasePresale_WithMerkleRoot() public {
        bytes32 root = 0xfeddcd9ebbb017ef7aedb6d5af6646b5cf1af84bfd1fc0bda8c59d068c3b12be;
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = 0x4e2ef3f4d279d23ce0933035d8c8fb3ce41acb03aa29a326c527a6c76b912f6e; // proof for makeAddr("user")
        _initPairWithPresale(root);

        vm.warp(block.timestamp + 1 days + 1);

        uint256 amountBefore = 1 ether;
        vm.deal(router, amountBefore);
        vm.prank(router);

        (uint256 nftNum,) = pair.purchasePresale{value: 1 ether}(
            1,
            1 ether,
            user, // nftRecipient
            proof, // merkleProof
            true, // isRouter
            user // routerCaller
        );
        assertEq(nftNum, 1);
    }

    function test_Revert_PurchasePresale_NotInMerkleRoot() public {
        bytes32 root = 0xfeddcd9ebbb017ef7aedb6d5af6646b5cf1af84bfd1fc0bda8c59d068c3b12be;
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = bytes32(0);
        _initPairWithPresale(root);

        vm.warp(block.timestamp + 1 days + 1);

        uint256 amountBefore = 1 ether;
        vm.deal(router, amountBefore);
        vm.prank(router);

        vm.expectRevert(PairERC7007ETH.PresaleMerkleNotApproved.selector);
        pair.purchasePresale{value: 1 ether}(
            1,
            1 ether,
            user, // nftRecipient
            proof, // merkleProof
            true, // isRouter
            user // routerCaller
        );
    }

    function test_Revert_PurchasePresale_NotInPresalePeriod() public {
        _initPairWithPresale(bytes32(0));
        vm.deal(router, 1 ether);

        vm.prank(router);
        vm.expectRevert(PairERC7007ETH.PresaleInactive.selector);
        pair.purchasePresale{value: 1 ether}(1, 1 ether, user, new bytes32[](0), true, user);

        vm.warp(block.timestamp + 3 days + 1);

        vm.prank(router);
        vm.expectRevert(PairERC7007ETH.PresaleInactive.selector);
        pair.purchasePresale{value: 1 ether}(1, 1 ether, user, new bytes32[](0), true, user);
    }

    function test_Revert_PurchasePresale_NotEnoughETH() public {
        _initPairWithPresale(bytes32(0));
        vm.warp(block.timestamp + 1 days + 1);
        vm.deal(router, 0.5 ether);

        vm.prank(router);
        vm.expectRevert(PairERC7007ETH.InsufficientInput.selector);
        pair.purchasePresale{value: 10_000}(1, 1 ether, user, new bytes32[](0), true, user);
    }

    function test_Revert_PurchasePresale_IfExceedLimit() public {
        _initPairWithPresale(bytes32(0));

        vm.warp(block.timestamp + 1 days + 1);

        vm.deal(router, 2 ether);
        vm.prank(router);
        vm.expectRevert(PairERC7007ETH.PresaleTooManyForAddress.selector);
        pair.purchasePresale{value: 1 ether}(
            2,
            1 ether,
            user, // nftRecipient
            new bytes32[](0), // merkleProof
            true, // isRouter
            user // routerCaller
        );

        address user2 = makeAddr("user2");
        vm.prank(router);
        pair.purchasePresale{value: 1 ether}(
            1,
            1 ether,
            user2, // nftRecipient
            new bytes32[](0), // merkleProof
            true, // isRouter
            user2 // routerCaller
        );

        vm.prank(router);
        vm.expectRevert(PairERC7007ETH.PresaleTooManyForAddress.selector);
        pair.purchasePresale{value: 1 ether}(
            1,
            1 ether,
            user2, // nftRecipient
            new bytes32[](0), // merkleProof
            true, // isRouter
            user2 // routerCaller
        );
    }

    function test_GetPresaleQuote() public {
        _initPairWithPresale(bytes32(0));

        vm.warp(block.timestamp + 1 days + 1);

        (uint256 inputAmount, uint256 revealFee, uint256 royaltyAmount) = pair.getPresaleQuote(0, 1);

        assertEq(revealFee, revealFeePerNFT);

        uint256 expectedRoyaltyAmount = bondingCurveFixedPrice * 500 / 10_000;
        assertEq(royaltyAmount, expectedRoyaltyAmount);

        vm.deal(router, 1 ether);
        vm.prank(router);

        (uint256 nftNum, uint256 amount) = pair.purchasePresale{value: inputAmount}(
            1,
            1 ether,
            user, // nftRecipient
            new bytes32[](0), // merkleProof
            true, // isRouter
            user // routerCaller
        );
        assertEq(amount, inputAmount);
        assertEq(nftNum, 1);
    }

    function test_GetBuyNFTQuote() public {
        _initPairWithDefaultConfig();

        (uint256 inputAmount, uint256 revealFee, uint256 royaltyAmount) = pair.getBuyNFTQuote(0, 1, false);
        assertEq(revealFee, revealFeePerNFT);
        uint256 expectedRoyaltyAmount = bondingCurveFixedPrice * 500 / 10_000;
        assertEq(royaltyAmount, expectedRoyaltyAmount);
        uint256 fee = bondingCurveFixedPrice * 200 / 10_000;
        assertEq(inputAmount, bondingCurveFixedPrice + fee + royaltyAmount + revealFee);

        (uint256 inputAmount2,,) = pair.getBuyNFTQuote(0, 1, true);
        assertEq(inputAmount2, bondingCurveFixedPrice + fee + royaltyAmount);
    }

    function test_SwapTokenForNFTs_unIssued() public {
        _initPairWithDefaultConfig();

        uint256 amountBefore = 1 ether;
        vm.deal(router, amountBefore);
        vm.prank(router);

        (uint256 nftNum, uint256 amount) = pair.swapTokenForNFTs{value: 1 ether}(
            10, // nftNum
            3 ether, // maxExpectedTokenInput
            user, // nftRecipient
            true, // isRouter
            user // routerCaller
        );

        uint256 revealFee = revealFeePerNFT * 10;
        uint256 price = bondingCurveFixedPrice * 10;
        uint256 roaylty = price * 500 / 10_000;
        uint256 pairFee = price * 100 / 10_000;
        uint256 protocolFee = price * 100 / 10_000;

        assertEq(amount, revealFee + price + pairFee + protocolFee + roaylty, "cost is incorrect");

        uint256 amountAfter = router.balance;
        assertEq(amountBefore, amountAfter + amount, "user balance is incorrect");
        assertEq(nftNum, 10);
        assertEq(IERC721(nft).balanceOf(user), 10);
    }

    function test_SwapTokenForNFTs_Issued() public {
        _initPairWithDefaultConfig();

        vm.deal(router, 10 ether);
        vm.prank(router);

        pair.swapTokenForNFTs{value: 5 ether}(
            nftTotalSupply, // nftNum
            5 ether, // maxExpectedTokenInput
            user, // nftRecipient
            true, // isRouter
            user // routerCaller
        );
        assertEq(IERC721(nft).balanceOf(address(pair)), 0);
        assertEq(IERC721(nft).balanceOf(user), nftTotalSupply);

        uint256[] memory tokenIds = new uint256[](5);
        tokenIds[0] = 1;
        tokenIds[1] = 256;
        tokenIds[2] = 555;
        tokenIds[3] = 1234;
        tokenIds[4] = 7000;
        vm.startPrank(user);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            IERC721(nft).transferFrom(user, address(pair), tokenId);
        }
        vm.stopPrank();

        address user2 = makeAddr("user2");
        vm.prank(router);
        vm.expectRevert(PairERC7007ETH.SoldOut.selector);
        pair.swapTokenForNFTs{value: 5 ether}(
            10, // nftNum
            5 ether, // maxExpectedTokenInput
            user2, // nftRecipient
            true, // isRouter
            user2 // routerCaller
        );

        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            pair.syncNFTStatus(tokenId);
        }

        vm.prank(router);
        (uint256 nftNum,) = pair.swapTokenForNFTs{value: 5 ether}(
            10, // nftNum
            5 ether, // maxExpectedTokenInput
            user2, // nftRecipient
            true, // isRouter
            user2 // routerCaller
        );
        assertEq(nftNum, tokenIds.length);
    }

    function test_SwapTokenForSpecificNFTs() public {
        _initPairWithDefaultConfig();
        vm.deal(router, 10 ether);
        vm.prank(router);
        pair.swapTokenForNFTs{value: 5 ether}(
            nftTotalSupply, // nftNum
            5 ether, // maxExpectedTokenInput
            user, // nftRecipient
            true, // isRouter
            user // routerCaller
        );
        assertEq(IERC721(nft).balanceOf(address(pair)), 0);
        assertEq(IERC721(nft).balanceOf(user), nftTotalSupply);

        uint256[] memory tokenIds = new uint256[](5);
        tokenIds[0] = 11;
        tokenIds[1] = 1256;
        tokenIds[2] = 1555;
        tokenIds[3] = 2234;
        tokenIds[4] = 7003;

        vm.startPrank(user);
        // transfer nfts to pair and sync status
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            IERC721(nft).transferFrom(user, address(pair), tokenId);
            pair.syncNFTStatus(tokenId);
        }
        vm.stopPrank();

        address user2 = makeAddr("user2");
        assembly {
            mstore(tokenIds, 3)
        }

        vm.prank(router);
        // user2 buy 3 nfts
        (uint256 nftNum, uint256 amount) =
            pair.swapTokenForSpecificNFTs{value: 1 ether}(tokenIds, 0, 1 ether, user2, true, user2);

        uint256 price = bondingCurveFixedPrice * 3;
        uint256 roaylty = price * 500 / 10_000;
        uint256 pairFee = price * 100 / 10_000;
        uint256 protocolFee = price * 100 / 10_000;

        assertEq(amount, price + pairFee + protocolFee + roaylty, "cost is incorrect");
        assertEq(nftNum, 3);

        address user3 = makeAddr("user3");
        assembly {
            mstore(tokenIds, 5)
        }

        vm.prank(router);
        // user3 buy 5 nfts, but only 2 nfts left
        (nftNum,) = pair.swapTokenForSpecificNFTs{value: 1 ether}(tokenIds, 0, 1 ether, user3, true, user3);
        assertEq(nftNum, 2);
    }

    function test_GetSellNFTQuote() public {
        _initPairWithDefaultConfig();

        (uint256 outputAmount, uint256 royaltyAmount) = pair.getSellNFTQuote(0, 1);
        uint256 price = bondingCurveFixedPrice;
        uint256 fee = price * 200 / 10_000;
        uint256 expectedRoyaltyAmount = (price - fee) * 500 / 10_000;
        assertEq(expectedRoyaltyAmount, royaltyAmount);
        assertEq(outputAmount, price - fee - expectedRoyaltyAmount);
    }

    function test_SwapNFTsForToken() public {
        _initPairWithDefaultConfig();

        vm.deal(router, 1 ether);
        vm.prank(router);
        pair.swapTokenForNFTs{value: 1 ether}(
            20, // nftNum
            1 ether, // maxExpectedTokenInput
            user, // nftRecipient
            true, // isRouter
            user // routerCaller
        );

        uint256[] memory tokenIds = new uint256[](4);
        tokenIds[0] = 0;
        tokenIds[1] = 1;
        tokenIds[2] = 10;
        tokenIds[3] = 14;

        // Approve pair to transfer NFTs
        vm.deal(user, 0);
        vm.prank(user);
        IERC721(nft).setApprovalForAll(address(pair), true);

        vm.prank(router);
        uint256 amount = pair.swapNFTsForToken(
            tokenIds,
            0, // minExpectedTokenOutput
            payable(user), // tokenRecipient
            true, // isRouter
            user // routerCaller
        );

        uint256 price = bondingCurveFixedPrice * 4;
        uint256 pairFee = price * 100 / 10_000;
        uint256 protocolFee = price * 100 / 10_000;
        uint256 royalty = (price - pairFee - protocolFee) * 500 / 10_000;
        uint256 expectedAmount = price - pairFee - protocolFee - royalty;
        assertEq(amount, expectedAmount, "amount is incorrect");
        assertEq(user.balance, amount, "balance is incorrect");

        for (uint256 i; i < tokenIds.length; i++) {
            assertEq(IERC721(nft).ownerOf(tokenIds[i]), address(pair), "owner is incorrect");
        }
    }

    function testFuzz_BuyAndSell(
        uint256 nftNum
    ) public {
        nftNum = bound(nftNum, 1, nftTotalSupply);
        _initPairWithDefaultConfig();

        (uint256 amount,,) = pair.getBuyNFTQuote(0, nftNum, false);
        vm.deal(router, amount);
        vm.prank(router);
        pair.swapTokenForNFTs{value: amount}(nftNum, amount, user, true, user);

        uint256[] memory tokenIds = new uint256[](nftNum);
        for (uint256 i; i < nftNum; i++) {
            tokenIds[i] = i;
        }
        vm.prank(user);
        IERC721(nft).setApprovalForAll(address(pair), true);

        vm.prank(router);
        uint256 amountOut = pair.swapNFTsForToken(tokenIds, 0, payable(user), true, user);
        (uint256 expectedAmountOut,) = pair.getSellNFTQuote(0, tokenIds.length);
        assertEq(amountOut, expectedAmountOut);
        assertEq(address(pair).balance, 0);

        // another user may buy already issued NFTs
        address user2 = makeAddr("user2");
        (amount,,) = pair.getBuyNFTQuote(0, nftNum, false);
        vm.deal(router, amount);
        vm.prank(router);
        pair.swapTokenForNFTs{value: amount}(nftNum, amount, user2, true, user2);
    }

    function test_Revert_BuyOrSellNFT_IFSaleInactive() public {
        _initPairWithPresale(bytes32(0));
        vm.deal(router, 1 ether);

        vm.prank(router);
        vm.expectRevert(PairERC7007ETH.SaleInactive.selector);
        pair.swapTokenForNFTs{value: 1 ether}(
            1, // nftNum
            1 ether, // maxExpectedTokenInput
            user, // nftRecipient
            true, // isRouter
            user // routerCaller
        );

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 0;
        vm.prank(router);
        vm.expectRevert(PairERC7007ETH.SaleInactive.selector);
        pair.swapTokenForSpecificNFTs{value: 1 ether}(
            tokenIds,
            0,
            1 ether,
            user, // nftRecipient
            true, // isRouter
            user // routerCaller
        );

        vm.prank(router);
        vm.expectRevert(PairERC7007ETH.SaleInactive.selector);
        pair.swapNFTsForToken(
            tokenIds,
            1,
            payable(user), // nftRecipient
            true, // isRouter
            user // routerCaller
        );
    }

    function testFuzz_BuyAndSell_RandomPrice(
        uint256 price
    ) public {
        price = bound(price, 1, 1 ether);
        _initPairWithDefaultConfig();

        vm.deal(router, 10 ether);
        vm.prank(router);
        curve.setFixedPrice(price);

        (uint256 amount,,) = pair.getBuyNFTQuote(0, 3, false);
        vm.prank(router);
        pair.swapTokenForNFTs{value: amount}(3, amount, user, true, user);
    }
}
