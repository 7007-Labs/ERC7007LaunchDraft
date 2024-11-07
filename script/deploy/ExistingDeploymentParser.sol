// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import {ORAERC7007Impl} from "../../src/nft/ORAERC7007Impl.sol";
import {NFTCollectionFactory} from "../../src/nft/NFTCollectionFactory.sol";
import {SimpleCurve} from "../../src/bonding-curves/SimpleCurve.sol";
import {RoyaltyManager} from "../../src/RoyaltyManager.sol";
import {FeeManager} from "../../src/FeeManager.sol";
import {TransferManager} from "../../src/TransferManager.sol";
import {PairFactory} from "../../src/PairFactory.sol";
import {PairERC7007ETH} from "../../src/PairERC7007ETH.sol";
import {ERC7007Launch} from "../../src/ERC7007Launch.sol";
import {SimpleCurve} from "../../src/bonding-curves/SimpleCurve.sol";

struct DeployedBondingCurve {
    string name;
    address addr;
}

contract ExistingDeploymentParser is Script, Test {
    RoyaltyManager public royaltyManagerProxy;
    RoyaltyManager public royaltyManagerImpl;
    FeeManager public feeManagerImpl;
    FeeManager public feeManagerProxy;
    TransferManager public transferManager;
    ORAERC7007Impl public oraERC7007Impl;
    NFTCollectionFactory public nftCollectionFactoryImpl;
    NFTCollectionFactory public nftCollectionFactoryProxy;
    PairFactory public pairFactoryImpl;
    PairFactory public pairFactoryProxy;
    PairERC7007ETH public pairERC7007ETHImpl;
    ERC7007Launch public erc7007LaunchImpl;
    ERC7007Launch public erc7007LaunchProxy;

    DeployedBondingCurve[] public bondingCurves;

    function outputContractAddresses(
        string memory outputPath
    ) public {
        string memory parent_object = "parent object";

        string memory deployed_addresses = "addresses";
        vm.serializeAddress(deployed_addresses, "royaltyManagerImpl", address(royaltyManagerImpl));
        vm.serializeAddress(deployed_addresses, "royaltyManagerProxy", address(royaltyManagerProxy));
        vm.serializeAddress(deployed_addresses, "feeManagerImpl", address(feeManagerImpl));
        vm.serializeAddress(deployed_addresses, "feeManagerProxy", address(feeManagerProxy));
        vm.serializeAddress(deployed_addresses, "transferManager", address(transferManager));
        vm.serializeAddress(deployed_addresses, "oraERC7007Impl", address(oraERC7007Impl));
        vm.serializeAddress(deployed_addresses, "nftCollectionFactoryImpl", address(nftCollectionFactoryImpl));
        vm.serializeAddress(deployed_addresses, "nftCollectionFactoryProxy", address(nftCollectionFactoryProxy));
        vm.serializeAddress(deployed_addresses, "pairFactoryImpl", address(pairFactoryImpl));
        vm.serializeAddress(deployed_addresses, "pairFactoryProxy", address(pairFactoryProxy));
        vm.serializeAddress(deployed_addresses, "pairERC7007ETHImpl", address(pairERC7007ETHImpl));
        vm.serializeAddress(deployed_addresses, "erc7007LaunchImpl", address(erc7007LaunchImpl));
        string memory deployed_addresses_output =
            vm.serializeAddress(deployed_addresses, "erc7007LaunchProxy", address(erc7007LaunchProxy));

        string memory deployed_bondingCurves = "bondingCurves";
        uint256 bondingCurveNum = bondingCurves.length;
        for (uint256 i = 0; i < bondingCurveNum; ++i) {
            vm.serializeAddress(deployed_bondingCurves, bondingCurves[i].name, bondingCurves[i].addr);
        }
        string memory deployed_bondingCurves_output = bondingCurveNum == 0
            ? ""
            : vm.serializeAddress(
                deployed_bondingCurves,
                bondingCurves[bondingCurveNum - 1].name,
                address(bondingCurves[bondingCurveNum - 1].addr)
            );

        if (bondingCurveNum > 0) {
            vm.serializeString(parent_object, deployed_bondingCurves, deployed_bondingCurves_output);
        }
        string memory finalJson = vm.serializeString(parent_object, deployed_addresses, deployed_addresses_output);
        vm.writeJson(finalJson, outputPath);
    }

    function getOutputPath() internal returns (string memory) {
        string memory outputDir = string.concat("script/output/", vm.toString(block.chainid));
        vm.createDir(outputDir, true);
        return string.concat(outputDir, "/deploy.config.json");
    }
}
