// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IORAOracleDelegateCaller} from "../../src/interfaces/IORAOracleDelegateCaller.sol";
import {IAIOracle} from "../../src/interfaces/IAIOracle.sol";
import {IRandOracle} from ".../../src/interfaces/IRandOracle.sol";

contract MockORAOracleDelegateCaller is IORAOracleDelegateCaller {
    IAIOracle public immutable aiOracle;
    IRandOracle public immutable randOracle;

    constructor(address _aiOracle, address _randOracle) {
        aiOracle = IAIOracle(_aiOracle);
        randOracle = IRandOracle(_randOracle);
    }

    receive() external payable {}

    function addToAllowlist(
        address
    ) external {}

    function requestRandOracle(
        uint256 modelId,
        bytes calldata requestEntropy,
        address callbackAddr,
        uint64 gasLimit,
        bytes calldata callbackData
    ) external payable returns (uint256) {
        uint256 fee = randOracle.estimateFee(modelId, gasLimit);
        return randOracle.async{value: fee}(modelId, requestEntropy, callbackAddr, gasLimit, callbackData);
    }

    function requestAIOracleBatchInference(
        uint256 batchSize,
        uint256 modelId,
        bytes memory input,
        address callbackContract,
        uint64 gasLimit,
        bytes memory callbackData,
        IAIOracle.DA inputDA,
        IAIOracle.DA outputDA
    ) external payable returns (uint256) {
        uint256 fee = aiOracle.estimateFeeBatch(modelId, gasLimit, batchSize);
        return aiOracle.requestBatchInference{value: fee}(
            batchSize, modelId, input, callbackContract, gasLimit, callbackData, inputDA, outputDA
        );
    }
}
