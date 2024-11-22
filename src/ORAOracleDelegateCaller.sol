// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {IORAOracleDelegateCaller} from "./interfaces/IORAOracleDelegateCaller.sol";
import {IAIOracle} from "./interfaces/IAIOracle.sol";
import {IRandOracle} from "./interfaces/IRandOracle.sol";

contract ORAOracleDelegateCaller is IORAOracleDelegateCaller, Initializable, OwnableUpgradeable, UUPSUpgradeable {
    using Address for address payable;

    IAIOracle public immutable aiOracle;
    IRandOracle public immutable randOracle;

    event TokenWithdrawal(uint256 amount);

    constructor(IAIOracle _aiOracle, IRandOracle _randOracle) {
        aiOracle = _aiOracle;
        randOracle = _randOracle;
        _disableInitializers();
    }

    receive() external payable {}

    function initialize(
        address _owner
    ) external initializer {
        __Ownable_init(_owner);
    }

    function requestRandOracle(
        uint256 modelId,
        bytes calldata requestEntropy,
        address callbackAddr,
        uint64 gasLimit,
        bytes calldata callbackData
    ) external payable returns (uint256) {
        uint256 fee = randOracle.estimateFee(modelId, "", callbackAddr, gasLimit, callbackData);
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
    ) external payable returns (uint256) {}

    function withdrawETH(address recipient, uint256 amount) external onlyOwner {
        payable(recipient).sendValue(amount);
        emit TokenWithdrawal(amount);
    }

    /**
     * @dev Required by UUPS pattern
     */
    function _authorizeUpgrade(
        address
    ) internal override onlyOwner {}
}
