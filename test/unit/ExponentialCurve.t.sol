// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {StdUtils} from "forge-std/StdUtils.sol";
import {ExponentialCurve} from "../../src/bonding-curves/ExponentialCurve.sol";

contract ExponentialCurveTest is Test {
    ExponentialCurve curve;

    function setUp() public {
        curve = new ExponentialCurve();
        targetContract(address(curve));

        bytes4[] memory selectors = new bytes4[](2);
        selectors[0] = ExponentialCurve.getBuyPrice.selector;
        selectors[1] = ExponentialCurve.getSellPrice.selector;

        FuzzSelector memory selector = FuzzSelector({addr: address(curve), selectors: selectors});
        targetSelector(selector);
    }

    function invariant_BuyPriceIsUpOnly() external view {
        uint256 supplyNum;
        uint256 numItems;

        supplyNum = StdUtils.bound(supplyNum, 1, 70_070);
        numItems = StdUtils.bound(numItems, 1, supplyNum);

        uint256 price1 = curve.getBuyPrice(supplyNum, numItems);
        uint256 price2 = curve.getBuyPrice(supplyNum + 1, numItems);

        assertTrue(price2 > price1, "Price should increase with supply");
    }

    function test_KeyPoints() external view {
        uint256 price = curve.getBuyPrice(77, 10);
        assertEq(price, 1_609_151_099_447_434, "Buy price incorrect");

        price = curve.getSellPrice(87, 10);
        assertEq(price, 1_609_151_099_447_432, "Sell price incorrect");

        price = curve.getBuyPrice(7007, 1);
        assertEq(price, 11_768_282_715_324_656, "Buy price incorrect");
    }

    function test_GetBuyPrice_ZeroNumItems() external {
        vm.expectRevert();
        curve.getBuyPrice(1, 0);
    }

    function test_GetBuyPrice_ZeroSupply() external view {
        uint256 price = curve.getBuyPrice(0, 1);
        assertEq(price, 152_988_581_221_576, "Buy price incorrect");

        price = curve.getSellPrice(1, 1);
        assertEq(price, 152_988_581_221_574, "Sell price incorrect");
    }

    function invariant_SamePriceForSameSupplyAndAmount() external view {
        uint256 supplyNum;
        uint256 numItems;

        supplyNum = StdUtils.bound(supplyNum, 1, 70_070);
        numItems = StdUtils.bound(numItems, 1, supplyNum);

        assertEq(
            curve.getBuyPrice(supplyNum, numItems),
            curve.getSellPrice(supplyNum + numItems, numItems) + 2,
            /// to avoid precision loss
            "Buy price should equal sell price"
        );
    }

    function testFuzz_BuyPriceEqualsSellPrice(uint256 totalSupply, uint256 numItems) public view {
        // Bound inputs to prevent overflow/underflow
        totalSupply = bound(totalSupply, 1, 70_070);
        numItems = bound(numItems, 1, totalSupply);

        uint256 buyPrice = curve.getBuyPrice(totalSupply - numItems, numItems);
        uint256 sellPrice = curve.getSellPrice(totalSupply, numItems);
        if (numItems != 0) buyPrice -= 2;
        assertEq(buyPrice, sellPrice, "Buy price should equal sell price");
    }

    function testFuzz_Cumulative(uint256 iterations, uint256 batchSize) public view {
        uint256 cumulativeBuyPrice;
        iterations = bound(iterations, 1, 1000);
        batchSize = bound(batchSize, 1, 100);
        for (uint256 i; i < iterations; i++) {
            uint256 price = curve.getBuyPrice(i * batchSize, batchSize);
            cumulativeBuyPrice += price;
        }

        uint256 buyPrice = curve.getBuyPrice(0, iterations * batchSize);

        uint256 cumulativeSellPrice;

        uint256 totalSupply = iterations * batchSize;
        for (uint256 i; i < iterations; i++) {
            uint256 price = curve.getSellPrice(totalSupply - i * batchSize, batchSize);
            cumulativeSellPrice += price;
        }
        uint256 sellPrice = curve.getSellPrice(totalSupply, totalSupply);

        assertEq(buyPrice >= sellPrice, true);
        assertEq(cumulativeBuyPrice >= sellPrice, true);
        assertEq(buyPrice >= cumulativeSellPrice, true);
        assertEq(cumulativeBuyPrice >= cumulativeSellPrice, true);
    }
}
