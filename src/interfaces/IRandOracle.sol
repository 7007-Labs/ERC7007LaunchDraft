// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IRandOracle {
    /**
     * @dev Point, defined by a pair of coordinates
     */
    struct Point {
        bytes32 x;
        bytes32 y;
    }

    function async(
        uint256 modelId,
        bytes calldata requestEntropy,
        address callbackAddr,
        uint64 gasLimit,
        bytes calldata callbackData
    ) external payable returns (uint256);
    function invoke(uint256 requestId, bytes calldata output, bytes calldata) external;
    function verify(uint256 request_id, Point memory g_, Point memory r_hat_, bytes32 z_) external returns (bool);
    function contributeEntropy(
        bytes32 _publicEntropy
    ) external;
    function contributeQuantumEntropy(
        bytes32 _quantumEntropy
    ) external;
    function estimateFee(
        uint256 modelId,
        bytes calldata input,
        address callbackAddr,
        uint64 gasLimit,
        bytes calldata callbackData
    ) external view returns (uint256);

    event PublicEntropyUpdated(address indexed sender, bytes32 indexed publicEntropy);
    event MasterPKUpdated(address indexed sender, bytes32 indexed x, bytes32 indexed y);
    event QRNGUpdated(address indexed sender, address indexed newQRNG);

    event QuantumEntropyUpdated(address indexed sender, bytes32 indexed quantEntropy);
}
