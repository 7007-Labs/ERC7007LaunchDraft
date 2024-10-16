// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ICurve} from "./ICurve.sol";

interface IPairFactory {
    function createPairERC7007ETH(IERC721 _nft, ICurve _bondingCurve) external returns (address);
}
