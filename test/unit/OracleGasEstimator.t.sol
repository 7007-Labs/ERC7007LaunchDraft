// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {OracleGasEstimator} from "src/libraries/OracleGasEstimator.sol";

contract OracleGasEstimatorTest is Test {
    function testGetAIOracleCallbackGasLimit() public {
        // Test with small values
        uint256 num = 20;
        uint256 promptLength = 200;

        uint64 gas = OracleGasEstimator.getAIOracleCallbackGasLimit(num, promptLength);
        console.log("gas: %s", gas);
        // Test with medium values
        uint64 gas2 = OracleGasEstimator.getRandOracleCallbackGasLimit(num, promptLength);
        console.log("gasTotal: %s", gas2 + gas);
        uint256 gasprice = 30 gwei;
        uint256 fee = (gas + gas2) * gasprice + 20 * 0.0003 ether + 0.000003 ether;
        console.log("fee: %s", fee);
    }

    /*
    function testGetAIOracleCallbackGasLimitOverflow() public {
        // Test with values that should cause overflow
        vm.expectRevert(OracleGasEstimator.GaslimitOverflow.selector);
        OracleGasEstimator.getAIOracleCallbackGasLimit(type(uint256).max, type(uint256).max);
    }

    function testGetRandOracleCallbackGasLimit() public {
        // Test with small values
        uint64 gas = OracleGasEstimator.getRandOracleCallbackGasLimit(1, 100);
        assertGt(gas, 0, "Gas limit should be greater than 0");

        // Test with medium values
        gas = OracleGasEstimator.getRandOracleCallbackGasLimit(10, 1000);
        assertGt(gas, 0, "Gas limit should be greater than 0");

        // Test with larger values that don't overflow
        gas = OracleGasEstimator.getRandOracleCallbackGasLimit(100, 5000);
        assertGt(gas, 0, "Gas limit should be greater than 0");
    }

    function testGetRandOracleCallbackGasLimitOverflow() public {
        // Test with values that should cause overflow
        vm.expectRevert(OracleGasEstimator.GaslimitOverflow.selector);
        OracleGasEstimator.getRandOracleCallbackGasLimit(type(uint256).max, type(uint256).max);
    }

    function testGasLimitMonotonicIncrease() public {
        // Test that gas limits increase with increasing input values
        uint64 gas1 = OracleGasEstimator.getAIOracleCallbackGasLimit(1, 100);
        uint64 gas2 = OracleGasEstimator.getAIOracleCallbackGasLimit(2, 100);
        assertGt(gas2, gas1, "Gas should increase with number of requests");

        gas1 = OracleGasEstimator.getAIOracleCallbackGasLimit(1, 100);
        gas2 = OracleGasEstimator.getAIOracleCallbackGasLimit(1, 200);
        assertGt(gas2, gas1, "Gas should increase with prompt length");

        gas1 = OracleGasEstimator.getRandOracleCallbackGasLimit(1, 100);
        gas2 = OracleGasEstimator.getRandOracleCallbackGasLimit(2, 100);
        assertGt(gas2, gas1, "Gas should increase with number of requests");

        gas1 = OracleGasEstimator.getRandOracleCallbackGasLimit(1, 100);
        gas2 = OracleGasEstimator.getRandOracleCallbackGasLimit(1, 200);
        assertGt(gas2, gas1, "Gas should increase with prompt length");
    }*/
}
