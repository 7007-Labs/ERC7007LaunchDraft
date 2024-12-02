// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

import {ERC7007Launch} from "../../src/ERC7007Launch.sol";
import {IPair} from "../../src/interfaces/IPair.sol";
import {MockAIOracle} from "../../test/mocks/MockAIOracle.t.sol";
import {MockRandOracle} from "../../test/mocks/MockRandOracle.t.sol";
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

    function _configORA() internal override {
        aiOracle = address(new MockAIOracle());
        randOracle = address(new MockRandOracle());
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

    function launch(
        string calldata name,
        string calldata symbol,
        string calldata description,
        string calldata prompt,
        uint256 initialBuyNum,
        string calldata productWhitelistProof
    ) public {
        loadContractAddresses();

        bool nsfw = false;
        ERC7007Launch.LaunchParams memory params;
        params.metadataInitializer = abi.encode(name, symbol, description, nsfw);
        params.prompt = prompt;
        params.initialBuyNum = initialBuyNum;
        params.bondingCurve = bondingCurves[0].addr;
        params.provider = aiOracle;
        params.providerParams = abi.encode(50);

        bytes32[] memory proof = _parseProof(productWhitelistProof);
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        uint256 fee = erc7007LaunchProxy.estimateLaunchFee(params, aiOracle, randOracle);
        address pair = erc7007LaunchProxy.launch{value: fee}(params, proof);
        vm.stopBroadcast();
        console.log("Launched fee:", fee);
        console.log("Launched pair address:", pair);
        address nft = IPair(pair).nft();
        console.log("Launched nft address:", nft);
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
