// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ICurve} from "../../src/interfaces/ICurve.sol";

contract MockCurve is ICurve {
    uint256 fixedPrice;

    constructor(
        uint256 _fixedPrice
    ) {
        fixedPrice = _fixedPrice;
    }

    function setFixedPrice(
        uint256 _fixedPrice
    ) external {
        fixedPrice = _fixedPrice;
    }

    function getBuyPrice(uint256, /*totalSupply*/ uint256 numItems) external view returns (uint256) {
        return numItems * fixedPrice;
    }

    function getSellPrice(uint256, /*totalSupply*/ uint256 numItems) external view returns (uint256) {
        return numItems * fixedPrice;
    }
}
