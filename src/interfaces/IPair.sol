// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

interface IPair {
    enum PairType {
        LAUNCH
    }

    function getAssetRecipient() external returns (address);

    function changeAssetRecipient(address payable newRecipient) external;

    function pairType() external view returns (PairType);

    function token() external view returns (address _token);

    function nft() external view returns (address);
}
