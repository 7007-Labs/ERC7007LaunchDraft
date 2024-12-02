// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "forge-std/Test.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {ORAERC7007Impl} from "../../src/nft/ORAERC7007Impl.sol";
import {NFTCollectionFactory} from "../../src/nft/NFTCollectionFactory.sol";
import {ExponentialCurve} from "../../src/bonding-curves/ExponentialCurve.sol";
import {RoyaltyExecutor} from "../../src/RoyaltyExecutor.sol";
import {FeeManager} from "../../src/FeeManager.sol";
import {PairFactory} from "../../src/PairFactory.sol";
import {PairERC7007ETH} from "../../src/PairERC7007ETH.sol";
import {ERC7007Launch} from "../../src/ERC7007Launch.sol";
import {ORAOracleDelegateCaller} from "../../src/ORAOracleDelegateCaller.sol";

struct DeployedBondingCurve {
    string name;
    address addr;
}

contract ExistingDeploymentParser is Script {
    RoyaltyExecutor public royaltyExecutorProxy;
    RoyaltyExecutor public royaltyExecutorImpl;
    FeeManager public feeManagerImpl;
    FeeManager public feeManagerProxy;
    ORAOracleDelegateCaller public oraOracleDelegateCallerImpl;
    ORAOracleDelegateCaller public oraOracleDelegateCallerProxy;
    ORAERC7007Impl public oraERC7007Impl;
    NFTCollectionFactory public nftCollectionFactoryImpl;
    NFTCollectionFactory public nftCollectionFactoryProxy;
    PairFactory public pairFactoryImpl;
    PairFactory public pairFactoryProxy;
    PairERC7007ETH public pairERC7007ETHImpl;
    UpgradeableBeacon public pairERC7007ETHBeacon;
    ERC7007Launch public erc7007LaunchImpl;
    ERC7007Launch public erc7007LaunchProxy;

    DeployedBondingCurve[] public bondingCurves;

    function saveContractAddresses(
        string memory outputPath
    ) public {
        string memory parent_object = "parent object";

        string memory deployed_addresses = "addresses";
        vm.serializeAddress(deployed_addresses, "royaltyExecutorImpl", address(royaltyExecutorImpl));
        vm.serializeAddress(deployed_addresses, "royaltyExecutorProxy", address(royaltyExecutorProxy));
        vm.serializeAddress(deployed_addresses, "feeManagerImpl", address(feeManagerImpl));
        vm.serializeAddress(deployed_addresses, "feeManagerProxy", address(feeManagerProxy));
        vm.serializeAddress(deployed_addresses, "oraOracleDelegateCallerImpl", address(oraOracleDelegateCallerImpl));
        vm.serializeAddress(deployed_addresses, "oraOracleDelegateCallerProxy", address(oraOracleDelegateCallerProxy));
        vm.serializeAddress(deployed_addresses, "oraERC7007Impl", address(oraERC7007Impl));
        vm.serializeAddress(deployed_addresses, "nftCollectionFactoryImpl", address(nftCollectionFactoryImpl));
        vm.serializeAddress(deployed_addresses, "nftCollectionFactoryProxy", address(nftCollectionFactoryProxy));
        vm.serializeAddress(deployed_addresses, "pairFactoryImpl", address(pairFactoryImpl));
        vm.serializeAddress(deployed_addresses, "pairFactoryProxy", address(pairFactoryProxy));
        vm.serializeAddress(deployed_addresses, "pairERC7007ETHImpl", address(pairERC7007ETHImpl));
        vm.serializeAddress(deployed_addresses, "pairERC7007ETHBeacon", address(pairERC7007ETHBeacon));
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
        console.log("Contract addresses saved to", outputPath);
    }

    function saveContractAddresses() public {
        saveContractAddresses(getDefaultSavePath());
    }

    function loadContractAddresses(
        string memory path
    ) public {
        console.log("Load contract addresses on ChainID", block.chainid);

        string memory existingDeploymentData = vm.readFile(path);

        royaltyExecutorImpl =
            RoyaltyExecutor(stdJson.readAddress(existingDeploymentData, ".addresses.royaltyExecutorImpl"));
        royaltyExecutorProxy =
            RoyaltyExecutor(stdJson.readAddress(existingDeploymentData, ".addresses.royaltyExecutorProxy"));
        feeManagerImpl = FeeManager(stdJson.readAddress(existingDeploymentData, ".addresses.feeManagerImpl"));
        feeManagerProxy = FeeManager(stdJson.readAddress(existingDeploymentData, ".addresses.feeManagerProxy"));
        oraOracleDelegateCallerImpl = ORAOracleDelegateCaller(
            payable(stdJson.readAddress(existingDeploymentData, ".addresses.oraOracleDelegateCallerImpl"))
        );
        oraOracleDelegateCallerProxy = ORAOracleDelegateCaller(
            payable(stdJson.readAddress(existingDeploymentData, ".addresses.oraOracleDelegateCallerProxy"))
        );
        oraERC7007Impl = ORAERC7007Impl(stdJson.readAddress(existingDeploymentData, ".addresses.oraERC7007Impl"));
        nftCollectionFactoryImpl =
            NFTCollectionFactory(stdJson.readAddress(existingDeploymentData, ".addresses.nftCollectionFactoryImpl"));
        nftCollectionFactoryProxy =
            NFTCollectionFactory(stdJson.readAddress(existingDeploymentData, ".addresses.nftCollectionFactoryProxy"));
        pairFactoryImpl = PairFactory(stdJson.readAddress(existingDeploymentData, ".addresses.pairFactoryImpl"));
        pairFactoryProxy = PairFactory(stdJson.readAddress(existingDeploymentData, ".addresses.pairFactoryProxy"));
        pairERC7007ETHImpl =
            PairERC7007ETH(stdJson.readAddress(existingDeploymentData, ".addresses.pairERC7007ETHImpl"));
        pairERC7007ETHBeacon =
            UpgradeableBeacon(stdJson.readAddress(existingDeploymentData, ".addresses.pairERC7007ETHBeacon"));
        erc7007LaunchImpl =
            ERC7007Launch(payable(stdJson.readAddress(existingDeploymentData, ".addresses.erc7007LaunchImpl")));
        erc7007LaunchProxy =
            ERC7007Launch(payable(stdJson.readAddress(existingDeploymentData, ".addresses.erc7007LaunchProxy")));

        // Load bonding curves
        address exponentialCurveAddr = stdJson.readAddress(existingDeploymentData, ".bondingCurves.ExponentialCurve");
        if (exponentialCurveAddr != address(0)) {
            bondingCurves.push(DeployedBondingCurve({name: "ExponentialCurve", addr: exponentialCurveAddr}));
        }
    }

    function loadContractAddresses() public {
        loadContractAddresses(getDefaultSavePath());
    }

    function getDefaultSavePath() internal returns (string memory) {
        string memory outputDir = string.concat("script/output/", vm.toString(block.chainid));
        vm.createDir(outputDir, true);
        return string.concat(outputDir, "/deploy.config.json");
    }
}
