// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

contract MockRandOracle {
    bytes4 public constant callbackFunctionSelector = 0x9def5824;

    struct Request {
        bytes requestEntropy;
        address callbackAddr;
        uint64 gasLimit;
        bytes callbackData;
        uint256 randNum;
    }

    uint256 public seq;
    uint256 public gasPrice;
    mapping(uint256 requestId => Request) requests;

    constructor() {
        gasPrice = tx.gasprice;
    }

    function setGasPrice(
        uint256 _gasPrice
    ) external {
        gasPrice = _gasPrice;
    }

    function async(
        uint256 modelId,
        bytes calldata requestEntropy,
        address callbackAddr,
        uint64 gasLimit,
        bytes calldata callbackData
    ) external payable returns (uint256) {
        require(modelId == 0, "wrong modelId");
        uint256 requestId = seq;
        seq++;
        Request storage request = requests[requestId];
        request.callbackAddr = callbackAddr;
        request.requestEntropy = requestEntropy;
        request.gasLimit = gasLimit;
        request.callbackData = callbackData;
        return requestId;
    }

    function invoke(uint256 requestId, bytes calldata output, bytes calldata) external {
        Request storage request = requests[requestId];
        require(request.gasLimit != 0, "wrong rqeuestId");
        bytes32 data = keccak256(abi.encodePacked(msg.sender, requestId, output, block.timestamp));
        uint256 randNum = uint256(data);
        request.randNum = randNum;
        bytes memory _output = abi.encode(randNum);
        _invokeUint256(requestId, _output);
    }

    function _invokeUint256(uint256 requestId, bytes memory output) internal {
        Request storage request = requests[requestId];

        // invoke callback
        if (request.callbackAddr != address(0)) {
            uint256 outputUint256 = abi.decode(output, (uint256)); // convert bytes to uint256, for callback only
            bytes memory payload =
                abi.encodeWithSelector(callbackFunctionSelector, requestId, outputUint256, request.callbackData);
            (bool success, bytes memory data) = request.callbackAddr.call{gas: request.gasLimit}(payload);
            require(success, "callback fail");
            if (!success) {
                assembly {
                    revert(add(data, 32), mload(data))
                }
            }
        }
    }

    function contributeEntropy(
        bytes32 _publicEntropy
    ) external {}

    function estimateFee(
        uint256 modelId,
        bytes calldata, /* input */
        address, /* callbackAddr */
        uint64 gasLimit,
        bytes calldata /* callbackData */
    ) external view returns (uint256) {
        require(modelId == 0, "wrong modelId");
        uint256 protocolFee = 0;
        uint256 modelFee = 0.000003 ether;
        uint256 callbackFee = gasLimit * gasPrice;
        return protocolFee + modelFee + callbackFee;
    }
}
