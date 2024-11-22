// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IAIOracle} from "./IAIOracle.sol";

interface IORAOracleDelegateCaller {
    function requestRandOracle(
        uint256 modelId,
        bytes calldata requestEntropy,
        address callbackAddr,
        uint64 gasLimit,
        bytes calldata callbackData
    ) external payable returns (uint256);

    function requestAIOracleBatchInference(
        uint256 batchSize,
        uint256 modelId,
        bytes memory input,
        address callbackContract,
        uint64 gasLimit,
        bytes memory callbackData,
        IAIOracle.DA inputDA,
        IAIOracle.DA outputDA
    ) external payable returns (uint256);
}
