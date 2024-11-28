// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {IORAOracleDelegateCaller} from "./interfaces/IORAOracleDelegateCaller.sol";
import {IAIOracle} from "./interfaces/IAIOracle.sol";
import {IRandOracle} from "./interfaces/IRandOracle.sol";

/**
 * @title ORAOracleDelegateCaller
 * @notice This contract acts as an intermediary to manage access control and delegate calls to ORA's oracle services
 */
contract ORAOracleDelegateCaller is IORAOracleDelegateCaller, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    using Address for address payable;

    IAIOracle public immutable aiOracle;
    IRandOracle public immutable randOracle;

    /// @notice Address authorized to manage allowlist
    address public operator;

    /// @dev address => whether the address is allowed to call oracle functions
    mapping(address => bool) public allowlist;

    event ReceivedPayment(address sender, uint256 amount);
    event TokenWithdrawal(address recipient, uint256 amount);

    error ZeroAddress();
    error UnauthorizedCaller();

    modifier onlyAllowlist() {
        if (!allowlist[msg.sender]) revert UnauthorizedCaller();
        _;
    }

    constructor(IAIOracle _aiOracle, IRandOracle _randOracle) {
        aiOracle = _aiOracle;
        randOracle = _randOracle;
        _disableInitializers();
    }

    receive() external payable {
        emit ReceivedPayment(msg.sender, msg.value);
    }

    function initialize(
        address _owner
    ) external initializer {
        __Ownable_init(_owner);
    }

    /// @notice Delegate calls to randOracle
    function requestRandOracle(
        uint256 modelId,
        bytes calldata requestEntropy,
        address callbackAddr,
        uint64 gasLimit,
        bytes calldata callbackData
    ) external payable onlyAllowlist returns (uint256) {
        uint256 fee = randOracle.estimateFee(modelId, "", callbackAddr, gasLimit, callbackData);
        return randOracle.async{value: fee}(modelId, requestEntropy, callbackAddr, gasLimit, callbackData);
    }

    /// @notice Delegate calls to aiOracle
    function requestAIOracleBatchInference(
        uint256 batchSize,
        uint256 modelId,
        bytes memory input,
        address callbackContract,
        uint64 gasLimit,
        bytes memory callbackData,
        IAIOracle.DA inputDA,
        IAIOracle.DA outputDA
    ) external payable onlyAllowlist returns (uint256) {
        uint256 fee = aiOracle.estimateFeeBatch(modelId, gasLimit, batchSize);
        return aiOracle.requestBatchInference{value: fee}(
            batchSize, modelId, input, callbackContract, gasLimit, callbackData, inputDA, outputDA
        );
    }

    /// @notice Add an address to the whitelist
    function addToAllowlist(
        address _address
    ) external {
        if (msg.sender != operator) revert UnauthorizedCaller();
        allowlist[_address] = true;
    }

    function setOperator(
        address newOperator
    ) external onlyOwner {
        if (newOperator == address(0)) revert ZeroAddress();
        operator = newOperator;
    }

    function withdrawETH(address recipient, uint256 amount) external onlyOwner {
        payable(recipient).sendValue(amount);
        emit TokenWithdrawal(recipient, amount);
    }

    /**
     * @dev Required by UUPS pattern
     */
    function _authorizeUpgrade(
        address
    ) internal override onlyOwner {}
}
