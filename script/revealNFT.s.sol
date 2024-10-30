// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Script.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ORAERC7007Impl} from "../src/nft/ORAERC7007Impl.sol";
import {IAIOracle} from "../src/interfaces/IAIOracle.sol";

contract revealNFT is Script {
    function run() public {
        // ORAERC7007Impl nft = ORAERC7007Impl(0x7374A03f3F5B062e50D22025848BEB9d3736c964);
        ORAERC7007Impl nft = ORAERC7007Impl(0x70e69Ecb736b0dF00B34736F343147d630374415);
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        IAIOracle aiOracle = IAIOracle(0x0A0f4321214BB6C7811dD8a71cF587bdaF03f0A0);

        uint256 num = 2; //一次性开图的数量
        uint256 startTokenId = 20; //开图开始的tokenId, 每次调用后，需要手动修改此处
        uint256 gasLimit = 17_737 + (14_766 + 29_756) * num;

        // uint256 fee = aiOracle.estimateFeeBatch(modelId, gasLimit, num);
        uint256 fee = nft.estimateFee(num);
        console2.log("gasLimit: ", gasLimit);
        console2.log("fee: ", fee * 100 / 1e18);
        uint256[] memory tokenIds = new uint256[](num);
        for (uint256 i = 0; i < num; i++) {
            tokenIds[i] = startTokenId + i;
        }
        nft.reveal{value: fee}(tokenIds);
        vm.stopBroadcast();
    }
}
