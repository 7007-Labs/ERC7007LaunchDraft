// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {UD60x18, convert} from "@prb/math/src/UD60x18.sol";
import {ICurve} from "../interfaces/ICurve.sol";

contract ExponentialCurve is ICurve {
    UD60x18 internal constant a = UD60x18.wrap(246_766_791_823_112_224); // 1e18 * 0.52 * 7007 / 4.3428 / 3400
    UD60x18 internal constant t = UD60x18.wrap(619_780_219_780_219); // 1e18 * 4.3428/7007

    /// @dev 0.52 * (7007 / 4.3428) * (e^((4.3428/7007)*(S + n)) - e^((4.3428/7007)*S)) / ethPrice
    /// ethPrice = 3400 usd/ether
    function getPrice(UD60x18 totalSupply, UD60x18 amount) internal pure returns (UD60x18) {
        UD60x18 gap = t.mul(totalSupply.uncheckedAdd(amount)).exp().uncheckedSub(t.mul(totalSupply).exp());
        return a.mul(gap);
    }

    function getBuyPrice(uint256 totalSupply, uint256 numItems) external pure returns (uint256 inputValue) {
        return getPrice(convert(totalSupply), convert(numItems)).intoUint256();
    }

    function getSellPrice(uint256 totalSupply, uint256 numItems) external pure returns (uint256 outputValue) {
        return getPrice(convert(totalSupply - numItems), convert(numItems)).intoUint256();
    }
}
