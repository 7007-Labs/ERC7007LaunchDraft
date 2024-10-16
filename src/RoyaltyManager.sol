// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IRoyaltyManager} from "./interfaces/IRoyaltyManager.sol";

// todo: 需要考虑如果要限定某些collection或者是某些pair的话，怎么限定
contract RoyaltyManager is IRoyaltyManager {
    // todo: 修改接口
    function calculateRoyaltyFeeAndGetRecipient(address collection, uint256 tokenId, uint256 amount)
        external
        view
        returns (address, uint256)
    {
        return (address(0), 0);
    }
}
