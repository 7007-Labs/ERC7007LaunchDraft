// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {UD60x18, convert} from "@prb/math/src/UD60x18.sol";
import {ICurve} from "../interfaces/ICurve.sol";

contract ExponentialCurve is ICurve {
    UD60x18 private constant CURVE_MULTIPLIER = UD60x18.wrap(246_766_791_823_112_224); // 1e18 * 0.52 * 7007 / 4.3428 / 3400
    UD60x18 private constant EXP_FACTOR = UD60x18.wrap(619_780_219_780_219); // 1e18 * 4.3428/7007

    /// @dev 0.52 * (7007 / 4.3428) * (e^((4.3428/7007)*(S + n)) - e^((4.3428/7007)*S)) / ethPrice
    /// ethPrice = 3400 usd/ether
    function getPrice(UD60x18 totalSupply, UD60x18 numItems) private pure returns (UD60x18) {
        UD60x18 gap =
            EXP_FACTOR.mul(totalSupply.uncheckedAdd(numItems)).exp().uncheckedSub(EXP_FACTOR.mul(totalSupply).exp());

        return CURVE_MULTIPLIER.mul(gap);
    }

    /// @notice Calculate the price of purchasing numItems NFTs
    function getBuyPrice(uint256 totalSupply, uint256 numItems) external pure returns (uint256 inputValue) {
        require(numItems > 0, "numItems must be greater than 0");
        return getPrice(convert(totalSupply), convert(numItems)).intoUint256() + 2;
    }

    /// @notice Calculate the price of selling numItems NFTs
    function getSellPrice(uint256 totalSupply, uint256 numItems) external pure returns (uint256 outputValue) {
        require(totalSupply > 0 && numItems > 0, "totalSupply and numItems must be greater than 0");
        return getPrice(convert(totalSupply - numItems), convert(numItems)).intoUint256();
    }
}
