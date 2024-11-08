// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "../interfaces/IRandOracle.sol";

abstract contract RandOracleCallbackReceiver {
    IRandOracle public immutable randOracle;

    error UnauthorizedRandOracleCallbackSrouce(IRandOracle expected, IRandOracle found);

    constructor(
        IRandOracle _randOracle
    ) {
        randOracle = _randOracle;
    }

    modifier onlyRandOracleCallback() {
        IRandOracle foundRelayAddress = IRandOracle(msg.sender);
        if (foundRelayAddress != randOracle) {
            revert UnauthorizedRandOracleCallbackSrouce(randOracle, foundRelayAddress);
        }
        _;
    }

    function awaitRandOracle(uint256 requestId, uint256 output, bytes calldata callbackData) external virtual;
}
