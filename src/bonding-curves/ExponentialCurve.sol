// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {UD60x18, convert} from "@prb/math/src/UD60x18.sol";
import {ICurve} from "../interfaces/ICurve.sol";

contract ExponentialCurve is ICurve {
    UD60x18 private constant CURVE_MULTIPLIER = UD60x18.wrap(246_766_791_823_112_224); // a = 0.52 * 7007 / 4.3428 / 3400
    UD60x18 private constant EXP_FACTOR = UD60x18.wrap(619_780_219_780_219); // t = 4.3428/7007

    /// @dev 0.52 * (7007 / 4.3428) * (e^((4.3428/7007)*(S + n)) - e^((4.3428/7007)*S)) / ethPrice
    /// ethPrice = 3400 usd/ether
    function getPrice(UD60x18 totalSupply, UD60x18 numItems) private pure returns (UD60x18) {
        require(
            numItems.gt(convert(0)) && totalSupply.gte(convert(0)), "totalSupply and numItems must be greater than 0"
        );

        UD60x18 gap =
            EXP_FACTOR.mul(totalSupply.uncheckedAdd(numItems)).exp().uncheckedSub(EXP_FACTOR.mul(totalSupply).exp());

        return CURVE_MULTIPLIER.mul(gap);
    }

    /// @notice 计算购买 numItems NFT 的价格
    function getBuyPrice(uint256 totalSupply, uint256 numItems) external pure returns (uint256 inputValue) {
        return getPrice(convert(totalSupply), convert(numItems)).intoUint256();
    }

    /// @notice 计算卖出 numItems NFT 的价格
    function getSellPrice(uint256 totalSupply, uint256 numItems) external pure returns (uint256 outputValue) {
        return getPrice(convert(totalSupply - numItems), convert(numItems)).intoUint256();
    }
}
