// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ICurve} from "../interfaces/ICurve.sol";
import {IPair} from "../interfaces/Ipair.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

// 示例，采用friend.tech的曲线 ref: https://www.cookbook.dev/protocols/Friend-Tech
contract SimpleCurve is ICurve {
    function getPrice(uint256 supply, uint256 amount) internal pure returns (uint256) {
        uint256 sum1 = supply == 0 ? 0 : (supply - 1) * (supply) * (2 * (supply - 1) + 1) / 6;
        uint256 sum2 = supply == 0 && amount == 1
            ? 0
            : (supply - 1 + amount) * (supply + amount) * (2 * (supply - 1 + amount) + 1) / 6;
        uint256 summation = sum2 - sum1;
        return summation * 1 ether / 16000;
    }

    function getBuyPrice(address pair, uint256 numItems) external view returns (uint256 inputValue) {
        address nft = IPair(pair).nft();
        uint256 pairBalance = IERC721(nft).balanceOf(pair);
        return getPrice(pairBalance, numItems);
    }

    function getSellPrice(address pair, uint256 numItems) external view returns (uint256 outputValue) {
        address nft = IPair(pair).nft();
        uint256 pairBalance = IERC721(nft).balanceOf(pair);
        return getPrice(pairBalance - numItems, numItems);
    }
}
