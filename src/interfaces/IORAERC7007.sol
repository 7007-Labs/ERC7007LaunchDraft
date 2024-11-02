// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IERC7007Updatable} from "./IERC7007Updatable.sol";

interface IORAERC7007 is IERC7007Updatable {
    function activate(uint256 _totalSupply, address _defaultNFTOwner, address _operator) external;
    function estimateFee(
        uint256 size
    ) external view returns (uint256);
    function reveal(
        uint256[] memory tokenIds
    ) external payable;
}
