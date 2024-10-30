// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Script.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ORAERC7007Impl} from "../src/nft/ORAERC7007Impl.sol";
import {IAIOracle} from "../src/interfaces/IAIOracle.sol";

contract Deploy_ORAERC7007 is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        address nftOwner = deployerAddress;
        address aiOracle = 0x0A0f4321214BB6C7811dD8a71cF587bdaF03f0A0;

        ORAERC7007Impl nftImpl = new ORAERC7007Impl(IAIOracle(aiOracle));

        // 仅单独测试时使用
        ERC1967Proxy proxy = new ERC1967Proxy(address(nftImpl), "");
        ORAERC7007Impl(address(proxy)).initialize("NFT name", "NFT", "a small dog", nftOwner, false, 50);

        // owner调用mintAll
        // ORAERC7007Impl(address(proxy)).mintAll(nftOwner, 7007);

        vm.stopBroadcast();

        console.log("Deployer :", deployerAddress);
        console.log("ORAERC7007 implementation deployed at:", address(nftImpl));
        console.log("ORAERC7007 proxy deployed at:", address(proxy));
    }
}
