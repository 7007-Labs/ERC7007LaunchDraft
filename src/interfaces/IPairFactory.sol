// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ICurve} from "./ICurve.sol";
import {PairType} from "../enums/PairType.sol";

interface IPairFactory {
    function createPairERC7007ETH(
        address _nft,
        ICurve _bondingCurve,
        PairType _pairType,
        address _propertyChecker,
        address payable _assetRecipient,
        bytes calldata _data // 不同pairType可能会用到
    ) external payable returns (address);

    function isValidPair(
        address pair
    ) external view returns (bool);
}
