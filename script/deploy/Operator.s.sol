// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console} from "forge-std/Test.sol";

import {IPair} from "../../src/interfaces/IPair.sol";
import {ERC7007Launch} from "../../src/ERC7007Launch.sol";
import {DeployBase} from "./DeployBase.sol";

contract Operator is DeployBase {
    function verify() public {
        loadContractAddresses();
        verifyDeploy();
    }

    function launch(
        string calldata name,
        string calldata symbol,
        string calldata description,
        string calldata prompt,
        uint256 initialBuyNum
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

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);
        uint256 fee = erc7007LaunchProxy.estimateLaunchFee(params, aiOracle, randOracle);
        address pair = erc7007LaunchProxy.launch{value: fee}(params);
        vm.stopBroadcast();
        console.log("Launched fee:", fee);
        console.log("Launched pair address:", pair);
        address nft = IPair(pair).nft();
        console.log("Launched nft address:", nft);
    }

    function swapNFT(address pair, uint256 nftNum) public {
        loadContractAddresses();
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address user = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);
        (uint256 amount, uint256 revealFee,) = IPair(pair).getBuyNFTQuote(0, nftNum, false);
        erc7007LaunchProxy.swapTokenForNFTs{value: amount}(pair, nftNum, amount, user);
        vm.stopPrank();
        console.log("Bought nft:", nftNum);
        console.log("Bought nft reveal fee:", revealFee);
        console.log("Bought nft cost:", amount);
    }

    // Helper function to parse comma-separated hex strings into bytes32 array
    function _parseProof(
        string memory proofStr
    ) internal pure returns (bytes32[] memory) {
        // Split string by commas
        bytes memory proofBytes = bytes(proofStr);
        if (proofBytes.length == 0) return new bytes32[](0);
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
