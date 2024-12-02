// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";
import "forge-std/Test.sol";

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
}
