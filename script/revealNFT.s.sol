// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Script.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ORAERC7007Impl} from "../src/nft/ORAERC7007Impl.sol";
import {IAIOracle} from "../src/interfaces/IAIOracle.sol";

contract revealNFT is Script {
    function run() public {
        // ORAERC7007Impl nft = ORAERC7007Impl(0x7374A03f3F5B062e50D22025848BEB9d3736c964);
        /*
        ORAERC7007Impl nft = ORAERC7007Impl(0xC1C2EaeDbC4dDF596D4430e1011B24739d7f5c06);
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        IAIOracle aiOracle = IAIOracle(0x0A0f4321214BB6C7811dD8a71cF587bdaF03f0A0);

        uint256 num = 1; //一次性开图的数量
        uint256 startTokenId = 0; //开图开始的tokenId, 每次调用后，需要手动修改此处

        uint256[] memory tokenIds1 = new uint256[](num);
        for (uint256 i = 0; i < num; i++) {
            tokenIds1[i] = startTokenId + i;
        }
        uint256 fee = nft.estimateFee(num);
        console2.log("fee: ", num, fee);
        nft.reveal{value: fee}(tokenIds1);

        num = 10;
        startTokenId = 1;
        uint256[] memory tokenIds2 = new uint256[](num);
        for (uint256 i = 0; i < num; i++) {
            tokenIds2[i] = startTokenId + i;
        }
        fee = nft.estimateFee(num);
        console2.log("fee: ", num, fee);
        nft.reveal{value: fee}(tokenIds2);

        num = 50;
        startTokenId = 11;
        uint256[] memory tokenIds3 = new uint256[](num);
        for (uint256 i = 0; i < num; i++) {
            tokenIds3[i] = startTokenId + i;
        }
        fee = nft.estimateFee(num);
        console2.log("fee: ", num, fee);
        nft.reveal{value: fee}(tokenIds3);
        vm.stopBroadcast();
        */
    }
}
