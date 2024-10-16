// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface ICurve {
    function getBuyInfo(uint256 numItems, uint256 reserveToken, uint256 reserveNFT)
        external
        view
        returns (uint256 inputValue);

    function getSellInfo(uint256 numItems, uint256 reserveToken, uint256 reserveNFT)
        external
        view
        returns (uint256 outputValue);
}
