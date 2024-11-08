// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {PairType} from "../../src/enums/PairType.sol";
import {PairERC7007ETH} from "../../src/PairERC7007ETH.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ICurve} from "../../src/interfaces/ICurve.sol";
import {IPairFactory} from "../../src/interfaces/IPairFactory.sol";
import {IRoyaltyManager} from "../../src/interfaces/IRoyaltyManager.sol";
import {IFeeManager} from "../../src/interfaces/IFeeManager.sol";
import {ITransferManager} from "../../src/interfaces/ITransferManager.sol";
import {IORAERC7007} from "../../src/interfaces/IORAERC7007.sol";

contract MockERC7007 is ERC721 {
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    uint256 public totalSupply;
    mapping(uint256 => bool) private revealed;

    constructor(
        uint256 totalSupply_
    ) ERC721("Test NFT", "TNFT") {
        totalSupply = totalSupply_;
    }

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }

    function activate(uint256 _totalSupply, address _defaultNFTOwner, address _operator) external {}

    function reveal(
        uint256[] calldata tokenIds
    ) external payable {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            require(revealed[tokenId] == false);
            revealed[tokenId] = true;
        }
    }

    function estimateRevealFee(
        uint256 numItems
    ) external pure returns (uint256) {
        return numItems * 0.01 ether;
    }
}

contract MockCurve is ICurve {
    uint256 FIXED_PRICE = 0.001 ether;

    function getBuyPrice(address, uint256 numItems) external view returns (uint256) {
        return numItems * FIXED_PRICE;
    }

    function getSellPrice(address, uint256 numItems) external view returns (uint256) {
        return numItems * FIXED_PRICE;
    }
}

contract MockFactory is IPairFactory {
    mapping(address => bool) public allowedRouters;

    function createPairERC7007ETH(
        address _owner,
        address _nft,
        address _bondingCurve,
        PairType _pairType,
        address _propertyChecker,
        bytes calldata extraParams // 不同pairType可能会用到
    ) external payable returns (address) {
        return _owner;
    }

    function setRouterAllowed(address router, bool allowed) external {
        allowedRouters[router] = allowed;
    }

    function isRouterAllowed(
        address router
    ) external view returns (bool) {
        return allowedRouters[router];
    }

    function isValidPair(
        address pair
    ) external view returns (bool) {
        return true;
    }
}

contract MockRoyaltyManager is IRoyaltyManager {
    function calculateRoyaltyFee(
        address,
        uint256,
        uint256 price
    ) external pure returns (address payable[] memory recipients, uint256[] memory amounts) {
        recipients = new address payable[](1);
        amounts = new uint256[](1);
        recipients[0] = payable(address(1));
        amounts[0] = price * 25 / 1000; // 2.5% royalty
    }
}

contract MockFeeManager is IFeeManager {
    mapping(address => PairFeeConfig) configs;

    function registerPair(address, uint16, uint16) external pure {}

    function calculateFees(
        address,
        uint256 price
    ) external pure returns (address payable[] memory recipients, uint256[] memory amounts) {
        recipients = new address payable[](1);
        amounts = new uint256[](1);
        recipients[0] = payable(address(2));
        amounts[0] = price * 10 / 1000; // 1% fee
    }

    function getConfig(
        address pair
    ) external view returns (PairFeeConfig memory) {
        return configs[pair];
    }
}

contract MockTransferManager is ITransferManager {
    function transferERC721(address nft, address from, address to, uint256[] calldata tokenIds) external {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            ERC721(nft).transferFrom(from, to, tokenIds[i]);
        }
    }

    function transferERC20(address token, address from, address to, uint256 amount) external {
        IERC20(token).transferFrom(from, to, amount);
    }

    function transferERC1155(
        address nft,
        address from,
        address to,
        uint256[] calldata ids,
        uint256[] calldata amounts
    ) external {
        IERC1155(nft).safeBatchTransferFrom(from, to, ids, amounts, "");
    }
}

contract PairERC7007ETHTest is Test {
    PairERC7007ETH public pair;
    MockERC7007 public nft;
    MockCurve public curve;
    MockFactory public factory;
    MockRoyaltyManager public royaltyManager;
    MockFeeManager public feeManager;
    MockTransferManager public transferManager;

    address public owner;
    address public user;
    uint256 public constant TOTAL_SUPPLY = 100;

    function setUp() public {
        owner = makeAddr("owner");
        user = makeAddr("user");

        nft = new MockERC7007(TOTAL_SUPPLY);
        curve = new MockCurve();
        factory = new MockFactory();
        royaltyManager = new MockRoyaltyManager();
        feeManager = new MockFeeManager();
        transferManager = new MockTransferManager();

        pair =
            new PairERC7007ETH(address(factory), address(royaltyManager), address(feeManager), address(transferManager));

        pair.initialize(
            owner,
            address(nft),
            curve,
            address(0), // No property checker
            TOTAL_SUPPLY
        );

        factory.setRouterAllowed(address(this), true);
        vm.deal(address(pair), 100 ether);
        vm.deal(user, 100 ether);
    }

    function test_Initialize() public {
        assertEq(pair.owner(), owner);
        assertEq(pair.nft(), address(nft));
        assertEq(address(pair.bondingCurve()), address(curve));
        assertEq(pair.nftTotalSupply(), TOTAL_SUPPLY);
    }

    function test_SwapTokenForNFTs() public {
        vm.startPrank(user);

        uint256 nftNum = 2;
        uint256 maxInput = 3 ether; // Price + fees + royalties + AIGC fee

        (uint256 numReceived, uint256 totalAmount) =
            pair.swapTokenForNFTs{value: maxInput}(nftNum, maxInput, user, false, address(0));

        assertEq(numReceived, nftNum);
        assertTrue(totalAmount > 0);
        assertEq(nft.balanceOf(user), nftNum);

        vm.stopPrank();
    }

    function test_SwapTokenForSpecificNFTs() public {
        // First reveal some NFTs
        uint256[] memory initialTokenIds = new uint256[](2);
        initialTokenIds[0] = 0;
        initialTokenIds[1] = 1;
        nft.reveal(initialTokenIds);

        vm.startPrank(user);

        uint256[] memory targetTokenIds = new uint256[](2);
        targetTokenIds[0] = 0;
        targetTokenIds[1] = 1;

        (uint256 numReceived, uint256 totalAmount) =
            pair.swapTokenForSpecificNFTs{value: 3 ether}(targetTokenIds, 2, 1, 3 ether, user, false, address(0));

        assertEq(numReceived, 2);
        assertTrue(totalAmount > 0);
        assertEq(nft.balanceOf(user), 2);

        vm.stopPrank();
    }

    function test_SwapNFTsForToken() public {
        // First buy some NFTs
        vm.startPrank(user);
        pair.swapTokenForNFTs{value: 3 ether}(2, 3 ether, user, false, address(0));

        uint256[] memory tokenIds = new uint256[](2);
        tokenIds[0] = 0;
        tokenIds[1] = 1;

        nft.setApprovalForAll(address(transferManager), true);
        uint256 balanceBefore = user.balance;

        uint256 outputAmount = pair.swapNFTsForToken(tokenIds, 1 ether, payable(user), false, address(0));

        assertTrue(outputAmount > 0);
        assertTrue(user.balance > balanceBefore);
        assertEq(nft.balanceOf(user), 0);

        vm.stopPrank();
    }

    function test_GetBuyNFTQuote() public {
        (uint256 inputAmount, uint256 aigcAmount, uint256 royaltyAmount) = pair.getBuyNFTQuote(0, 2, false);
        assertTrue(inputAmount > 0);
        assertTrue(aigcAmount > 0);
        assertTrue(royaltyAmount > 0);
    }

    function test_GetSellNFTQuote() public {
        (uint256 outputAmount, uint256 royaltyAmount) = pair.getSellNFTQuote(0, 2);
        assertTrue(outputAmount > 0);
        assertTrue(royaltyAmount > 0);
    }

    function test_SyncNFTStatus() public {
        // First reveal an NFT
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = 0;
        nft.reveal(tokenIds);

        pair.syncNFTStatus(0);

        // Transfer it away
        nft.transferFrom(address(pair), user, 0);
        pair.syncNFTStatus(0);

        // Try to buy it again (should fail)
        vm.startPrank(user);
        vm.expectRevert();
        uint256[] memory targetTokenIds = new uint256[](1);
        targetTokenIds[0] = 0;
        pair.swapTokenForSpecificNFTs{value: 2 ether}(targetTokenIds, 1, 1, 2 ether, user, false, address(0));
        vm.stopPrank();
    }

    receive() external payable {}
}
