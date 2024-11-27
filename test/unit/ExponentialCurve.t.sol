// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {ExponentialCurve} from "../../src/bonding-curves/ExponentialCurve.sol";

contract ExponentialCurveTest is Test {
    ExponentialCurve curve;

    function setUp() public {
        curve = new ExponentialCurve();
    }

    function test_GetBuyPrice() external view {
        uint256 price = curve.getBuyPrice(77, 10);
        assertEq(price, 1_609_151_099_447_432, "Buy price incorrect");
    }

    function test_GetSellPrice() external view {
        uint256 price = curve.getSellPrice(87, 10);
        assertEq(price, 1_609_151_099_447_432, "Sell price incorrect");
    }

    function test_GetBuyPrice_ZeroSupply() external view {
        uint256 price = curve.getBuyPrice(0, 1);
        assertEq(price, 152_988_581_221_574, "Buy price incorrect");
    }

    function test_GetBuyPrice_ZeroNumItems() external view {
        uint256 price = curve.getBuyPrice(1, 0);
        assertEq(price, 0, "Buy price incorrect");
    }

    function test_GetSellPrice_OneSupply() external view {
        uint256 price = curve.getSellPrice(1, 1);
        assertEq(price, 152_988_581_221_574, "Sell price incorrect");
    }

    function test_GetSellPrice_ZeroNumItems() external view {
        uint256 price = curve.getSellPrice(1, 0);
        assertEq(price, 0, "Sell price incorrect");
    }

    function testFuzz_BuyPriceEqualsSellPrice(uint256 totalSupply, uint256 numItems) public view {
        // Bound inputs to prevent overflow/underflow
        totalSupply = bound(totalSupply, 1, 70_070);
        numItems = bound(numItems, 1, totalSupply);

        uint256 buyPrice = curve.getBuyPrice(totalSupply - numItems, numItems);
        uint256 sellPrice = curve.getSellPrice(totalSupply, numItems);

        assertEq(buyPrice, sellPrice, "Buy price should equal sell price");
    }
}
