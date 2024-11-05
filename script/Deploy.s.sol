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

        // pairFactoryImpl

        // pairFactory

        // feeManagerImpl

        // feeManager feeManager.intialize

        // transferManager (pairFactory)

        // PairErc7007ETH (royaltyManager, feeManager, transferManager)

        // pairFactory.initialize (pairerc7007eth, transferManager)

        // launch

        // pairFactory addToAllowlist(launch)
        // pairFactory setRouterAllowed(launch)
    }
}
