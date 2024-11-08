// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {SimpleCurve} from "../../src/bonding-curves/SimpleCurve.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IPair} from "../../src/interfaces/IPair.sol";

contract MockERC721 is IERC721 {
    uint256 private balance;
    uint256 private _totalSupply;

    function setBalance(
        uint256 _balance
    ) external {
        balance = _balance;
    }

    function balanceOf(
        address
    ) external view returns (uint256) {
        return balance;
    }

    function ownerOf(
        uint256
    ) external pure returns (address) {
        revert("Not implemented");
    }

    function safeTransferFrom(address, address, uint256) external pure {
        revert("Not implemented");
    }

    function safeTransferFrom(address, address, uint256, bytes calldata) external pure {
        revert("Not implemented");
    }

    function transferFrom(address, address, uint256) external pure {
        revert("Not implemented");
    }

    function approve(address, uint256) external pure {
        revert("Not implemented");
    }

    function setApprovalForAll(address, bool) external pure {
        revert("Not implemented");
    }

    function getApproved(
        uint256
    ) external pure returns (address) {
        revert("Not implemented");
    }

    function isApprovedForAll(address, address) external pure returns (bool) {
        revert("Not implemented");
    }

    function supportsInterface(
        bytes4
    ) external pure returns (bool) {
        return true;
    }

    function setTotalSupply(
        uint256 value
    ) external {
        _totalSupply = value;
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }
}

contract MockPair {
    MockERC721 public nftContract;

    constructor(
        address _nft
    ) {
        nftContract = MockERC721(_nft);
    }

    function nft() external view returns (address) {
        return address(nftContract);
    }
}

contract SimpleCurveTest is Test {
    SimpleCurve public curve;
    MockERC721 public mockNFT;
    MockPair public mockPair;
    uint256 totalSupply = 100;

    function setUp() public {
        curve = new SimpleCurve();
        mockNFT = new MockERC721();
        mockNFT.setTotalSupply(totalSupply);
        mockPair = new MockPair(address(mockNFT));
    }
    /*
    function test_GetBuyPrice_ZeroSupply() public {
        mockNFT.setBalance(totalSupply);
        uint256 price = curve.getBuyPrice(address(mockPair), 2);
        console.log("price: %s", price);
        // assertEq(price, 0, "First token should be free");
    }

    function test_GetBuyPrice_SingleToken() public {
        mockNFT.setBalance(1);
        uint256 price = curve.getBuyPrice(address(mockPair), 1);
        // Price for second token should be 0.0625 ETH
        assertEq(price, 0.0625 ether, "Incorrect price for second token");
    }

    function test_GetBuyPrice_MultipleTokens() public {
        mockNFT.setBalance(2);
        uint256 price = curve.getBuyPrice(address(mockPair), 2);
        // Price for tokens 3 and 4 should be (2+3+4)*1e18/16000 = 0.5625 ETH
        assertEq(price, 0.5625 ether, "Incorrect price for multiple tokens");
    }

    function test_GetSellPrice_SingleToken() public {
        mockNFT.setBalance(0);
        uint256 price = curve.getSellPrice(address(mockPair), 1);
        console.log("sell price: %s", price);
        // Selling one token from supply of 2 should return 0.0625 ETH
        // assertEq(price, 0.0625 ether, "Incorrect sell price for single token");
    }

    function test_GetSellPrice_MultipleTokens() public {
        mockNFT.setBalance(4);
        uint256 price = curve.getSellPrice(address(mockPair), 2);
        // Selling 2 tokens from supply of 4 should return 0.375 ETH
        assertEq(price, 0.375 ether, "Incorrect sell price for multiple tokens");
    }

    function test_GetBuyPrice_LargeSupply() public {
        mockNFT.setBalance(100);
        uint256 price = curve.getBuyPrice(address(mockPair), 1);
        // Price increases quadratically with supply
        assertTrue(price > 0, "Price should be positive for large supply");
    }

    function test_GetSellPrice_RevertOnInsufficientBalance() public {
        mockNFT.setBalance(1);
        vm.expectRevert();
        curve.getSellPrice(address(mockPair), 2);
    }

    function test_PriceSymmetry() public {
        mockNFT.setBalance(5);
        uint256 buyPrice = curve.getBuyPrice(address(mockPair), 3);
        mockNFT.setBalance(8);
        uint256 sellPrice = curve.getSellPrice(address(mockPair), 3);
        assertEq(buyPrice, sellPrice, "Buy and sell prices should be symmetric");
    }
    */
}
