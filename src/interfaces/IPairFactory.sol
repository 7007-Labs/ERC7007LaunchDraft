// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {PairType} from "../enums/PairType.sol";

interface IPairFactory {
    function createPairERC7007ETH(
        address _owner,
        address _nft,
        PairType _pairType,
        address _propertyChecker,
        bytes calldata params // 不同pairType可能会用到
    ) external payable returns (address);

    function isRouterAllowed(
        address router
    ) external view returns (bool);
}
