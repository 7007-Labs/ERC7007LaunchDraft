// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Script.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract Deploy is Script {
    function run() public {
        // royaltyManager = new RoyaltyManager

        // nftImpl = new ORAERC7007Impl // aiOracle

        // nftFactoryImpl = new NFTFactory

        // nftFactory nftFactory.initialize

        // PairErc7007ETH (royaltyManager, feeManager)

        // pairFactoryImpl

        // pairFactory
    }
}
