// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

library OracleGasEstimator {
    error GaslimitOverflow();

    function getAIOracleCallbackGasLimit(uint256 num, uint256 promptLength) internal pure returns (uint64) {
        uint256 numTimesPromptLen = num * promptLength;
        uint256 baseGas = num * 105_205 + numTimesPromptLen + promptLength / 32 * 2100 + 14_300; // storage sload sstore
        uint256 wordSize = (num * 191 * 32 + numTimesPromptLen * 6) / 32;
        uint256 memoryGas = (wordSize * wordSize) / 512 + wordSize * 3; // memory expans cost
        uint256 totalGas = baseGas + memoryGas;
        if (num > 1) {
            totalGas = totalGas * 110 / 100;
        }
        if (totalGas > type(uint64).max) revert GaslimitOverflow();
        return uint64(totalGas);
    }

    function getRandOracleCallbackGasLimit(uint256 num, uint256 promptLength) internal pure returns (uint64) {
        uint256 batchPromptLength = num * (99 + promptLength) + 4;
        uint256 slotNum = (batchPromptLength + 31) / 32;
        uint256 baseGas = slotNum * 23_764 + num * 32_100 + 353_700;
        uint256 wordSize = slotNum * 26 + num * (32 * 200 + promptLength * 23) / 32;
        uint256 memoryGas = (wordSize * wordSize) / 512 + wordSize * 3;
        uint256 totalGas = baseGas + memoryGas;
        if (num > 1) {
            totalGas = totalGas * 110 / 100;
        }
        if (totalGas > type(uint64).max) revert GaslimitOverflow();
        return uint64(totalGas);
    }
}
