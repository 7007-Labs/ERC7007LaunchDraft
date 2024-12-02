// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {DeployBase} from "./DeployBase.sol";

contract DeploySepolia is DeployBase {
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
}
