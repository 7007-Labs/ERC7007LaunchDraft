// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import {ERC7007Launch} from "../../src/ERC7007Launch.sol";
import {DeployBase} from "./DeployBase.sol";

contract DeployLocal is DeployBase, Test {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        admin = deployer;
        protocolFeeRecipient = deployer;
        vm.startBroadcast(deployerPrivateKey);
        deploy();
        vm.stopBroadcast();
        saveContractAddresses();
    }

    function configProductWhitelist(
        bytes32 root
    ) public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        loadContractAddresses();
        vm.startBroadcast(deployerPrivateKey);
        erc7007LaunchProxy.setWhitelistMerkleRoot(root);
        vm.stopBroadcast();

        assertEq(erc7007LaunchProxy.whitelistMerkleRoot(), root);
    }

    function verify() public {
        loadContractAddresses();
        verifyDeploy();
    }

    function launch() public {
        // Parse command line arguments
        bytes memory metadataInitializer = vm.parseBytes("METADATA_INITIALIZER");
        string memory prompt = vm.envString("PROMPT");
        address provider = vm.envAddress("PROVIDER");
        bytes memory providerParams = vm.parseBytes("PROVIDER_PARAMS");
        address bondingCurve = vm.envAddress("BONDING_CURVE");
        uint256 initialBuyNum = vm.envUint("INITIAL_BUY_NUM");

        // Create LaunchParams struct
        ERC7007Launch.LaunchParams memory params = ERC7007Launch.LaunchParams({
            metadataInitializer: metadataInitializer,
            prompt: prompt,
            provider: provider,
            providerParams: providerParams,
            bondingCurve: bondingCurve,
            initialBuyNum: initialBuyNum,
            presalePrice: 0,
            presaleMaxNum: 0,
            presaleStart: 0,
            presaleEnd: 0,
            presaleMerkleRoot: bytes32(0)
        });

        // Get whitelist proof from command line (comma-separated hex strings)
        string memory proofStr = vm.envString("WHITELIST_PROOF");
        bytes32[] memory proof = _parseProof(proofStr);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        loadContractAddresses();
        vm.startBroadcast(deployerPrivateKey);
        erc7007LaunchProxy.launch(params, proof);
        vm.stopBroadcast();
    }

    function launchWithPresale() public {
        // Parse command line arguments
        bytes memory metadataInitializer = vm.parseBytes("METADATA_INITIALIZER");
        string memory prompt = vm.envString("PROMPT");
        address provider = vm.envAddress("PROVIDER");
        bytes memory providerParams = vm.parseBytes("PROVIDER_PARAMS");
        address bondingCurve = vm.envAddress("BONDING_CURVE");
        uint256 initialBuyNum = vm.envUint("INITIAL_BUY_NUM");
        uint96 presalePrice = uint96(vm.envUint("PRESALE_PRICE"));
        uint32 presaleMaxNum = uint32(vm.envUint("PRESALE_MAX_NUM"));
        uint64 presaleStart = uint64(vm.envUint("PRESALE_START"));
        uint64 presaleEnd = uint64(vm.envUint("PRESALE_END"));
        bytes32 presaleMerkleRoot = vm.envBytes32("PRESALE_MERKLE_ROOT");

        // Create LaunchParams struct
        ERC7007Launch.LaunchParams memory params = ERC7007Launch.LaunchParams({
            metadataInitializer: metadataInitializer,
            prompt: prompt,
            provider: provider,
            providerParams: providerParams,
            bondingCurve: bondingCurve,
            initialBuyNum: initialBuyNum,
            presalePrice: presalePrice,
            presaleMaxNum: presaleMaxNum,
            presaleStart: presaleStart,
            presaleEnd: presaleEnd,
            presaleMerkleRoot: presaleMerkleRoot
        });

        // Get whitelist proof from command line (comma-separated hex strings)
        string memory proofStr = vm.envString("WHITELIST_PROOF");
        bytes32[] memory proof = _parseProof(proofStr);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        loadContractAddresses();
        vm.startBroadcast(deployerPrivateKey);
        erc7007LaunchProxy.launch(params, proof);
        vm.stopBroadcast();
    }

    // Helper function to parse comma-separated hex strings into bytes32 array
    function _parseProof(
        string memory proofStr
    ) internal pure returns (bytes32[] memory) {
        // Split string by commas
        bytes memory proofBytes = bytes(proofStr);
        uint256 count = 1;
        for (uint256 i = 0; i < proofBytes.length; i++) {
            if (proofBytes[i] == ",") count++;
        }

        bytes32[] memory proof = new bytes32[](count);
        uint256 start = 0;
        uint256 current = 0;

        for (uint256 i = 0; i <= proofBytes.length; i++) {
            if (i == proofBytes.length || proofBytes[i] == ",") {
                bytes memory temp = new bytes(i - start);
                for (uint256 j = start; j < i; j++) {
                    temp[j - start] = proofBytes[j];
                }
                proof[current] = bytes32(vm.parseBytes(string(temp)));
                current++;
                start = i + 1;
            }
        }

        return proof;
    }
}
