// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IAIOracle} from "../../src/interfaces/IAIOracle.sol";

contract MockAIOracle {
    bytes4 public constant callbackFunctionSelector = 0xb0347814;
    mapping(uint256 => uint256) public modelFee;
    mapping(uint256 => bool) public modelExists;
    uint256 gasPrice;
    uint256 seq;

    struct RequestData {
        address account;
        uint256 requestId;
        uint256 modelId;
        bytes input;
        address callbackContract;
        uint64 gasLimit;
        bytes callbackData;
    }

    mapping(uint256 => RequestData) requests;

    constructor() {
        modelExists[50] = true;
        modelFee[50] = 0.0003 ether;
        gasPrice = tx.gasprice;
    }

    modifier ifModelExists(
        uint256 modelId
    ) {
        require(modelExists[modelId], "model does not exist");
        _;
    }

    function addModel(uint256 modelId, uint256 fee) external {
        modelExists[modelId] = true;
        modelFee[modelId] = fee;
    }

    function estimateFee(uint256 modelId, uint256 gasLimit) public view ifModelExists(modelId) returns (uint256) {
        return modelFee[modelId] + gasPrice * gasLimit;
    }

    function estimateFeeBatch(
        uint256 modelId,
        uint256 gasLimit,
        uint256 batchSize
    ) public view ifModelExists(modelId) returns (uint256) {
        return batchSize * modelFee[modelId] + gasPrice * gasLimit;
    }

    function requestBatchInference(
        uint256 batchSize,
        uint256 modelId,
        bytes memory input,
        address callbackContract,
        uint64 gasLimit,
        bytes memory callbackData,
        IAIOracle.DA, /* inputDA */
        IAIOracle.DA /* outputDA */
    ) external payable returns (uint256) {
        // validate params
        uint256 fee = estimateFeeBatch(modelId, gasLimit, batchSize);
        require(msg.value >= fee, "insufficient fee");

        uint256 requestId = seq;
        seq++;

        RequestData storage request = requests[requestId];
        request.account = msg.sender;
        request.requestId = requestId;
        request.modelId = modelId;
        request.input = input;
        request.callbackContract = callbackContract;
        request.gasLimit = gasLimit;
        request.callbackData = callbackData;

        return requestId;
    }

    function invokeCallback(uint256 requestId, bytes calldata output) external {
        RequestData storage request = requests[requestId];
        if (request.callbackContract != address(0)) {
            bytes memory payload =
                abi.encodeWithSelector(callbackFunctionSelector, requestId, output, request.callbackData);
            (bool success, bytes memory data) = request.callbackContract.call{gas: request.gasLimit}(payload);
            require(success, "failed to call selector");
            if (!success) {
                assembly {
                    revert(add(data, 32), mload(data))
                }
            }
        }
    }

    function isFinalized(
        uint256 requestId
    ) external view returns (bool) {
        RequestData storage request = requests[requestId];
        return request.account != address(0);
    }

    function updateGasLimit(uint256 requestId, uint64 gasLimit) external {
        RequestData storage request = requests[requestId];
        request.gasLimit = gasLimit;
    }

    function makeOutput(
        uint256 num
    ) public pure returns (bytes memory) {
        bytes memory pattern = bytes("\x00\x00\x00.QmY3GuNcscmzD6CnVjKWeqfSPaVXb2gck75HUrtq8Yf3su");
        uint256 patternSize = pattern.length;
        uint256 totalLength = 4 + num * patternSize;
        bytes memory result = new bytes(totalLength);
        for (uint256 i = 0; i < 4; i++) {
            result[i] = bytes1(uint8(num >> (8 * (3 - i))));
        }
        for (uint256 i = 0; i < num; i++) {
            for (uint256 j = 0; j < patternSize; j++) {
                result[4 + i * patternSize + j] = pattern[j];
            }
        }
        return result;
    }
}
