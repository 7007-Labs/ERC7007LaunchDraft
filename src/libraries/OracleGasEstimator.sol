// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

library OracleGasEstimator {
    error GaslimitOverflow();

    function getAIOracleCallbackGasLimit(uint256 num, uint256 promptLength) internal pure returns (uint64) {
        uint256 numTimesPromptLen = num * promptLength;
        uint256 baseGas = num * 83_105 + numTimesPromptLen + promptLength / 32 * 2100 + 14_300; // storage sload sstore
        uint256 wordSize = (num * 191 * 32 + numTimesPromptLen * 9) / 32;
        uint256 memoryGas = (wordSize * wordSize) / 512 + wordSize * 3; // memory expans cost
        uint256 totalGas = baseGas + memoryGas;

        totalGas = totalGas * 110 / 100;

        if (totalGas > type(uint64).max) revert GaslimitOverflow();
        return uint64(totalGas);
    }

    function getRandOracleCallbackGasLimit(uint256 num, uint256 promptLength) internal pure returns (uint64) {
        uint256 batchPromptLength = (num == 1 ? 101 : 188) + promptLength;
        uint256 slotNum = (batchPromptLength + 31) / 32;
        uint256 baseGas = slotNum * 22_120 + num * 44_700 + 353_700;
        uint256 wordSize = slotNum * 26;
        uint256 memoryGas = (wordSize * wordSize) / 512 + wordSize * 3;
        uint256 totalGas = baseGas + memoryGas;

        totalGas = totalGas * 110 / 100;

        if (totalGas > type(uint64).max) revert GaslimitOverflow();
        return uint64(totalGas);
    }
}
