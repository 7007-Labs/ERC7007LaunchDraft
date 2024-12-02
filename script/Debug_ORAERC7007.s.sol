// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Test.sol";
import {IAIOracle} from "../src/interfaces/IAIOracle.sol";
import {ORAERC7007Impl} from "../src/nft/ORAERC7007Impl.sol";
// import {ORAUtils} from "../src/utils/ORAutils.sol";

contract DebugORAERC7007 is Test {
    struct AICallbackRequestData {
        address account;
        uint256 requestId;
        uint256 modelId;
        bytes input;
        address callbackContract;
        uint64 gasLimit;
        bytes callbackData;
    }

    address aiOracle = 0x0A0f4321214BB6C7811dD8a71cF587bdaF03f0A0;

    constructor() {
        // change the params first
        vm.createSelectFork("arbitrum", 269_523_271);
    }

    function debug() external {
        uint256 requestId = 109_397;
        bool isFin = IAIOracle(aiOracle).isFinalized(requestId);
        console2.log("isFin: ", isFin);

        address nft = 0xc95a45f398c4A0dF741908C9DE96D2edeB1b886b;

        // bytes memory output = bytes();
        string memory str = vm.readFile("output_hex_string_format.txt");
        bytes memory output = vm.parseBytes(str);
        uint64 gl = getRequestGasLimit(requestId);
        console2.log("gasLimit: ", gl + 1000 + 2200 + 30_189 + 30_189);
        // console2.log("output size: ", output.length);
        // bytes[] memory res = this.decodeCIDs(output);
        // console2.log("s: ", str);
        vm.prank(aiOracle);
        ORAERC7007Impl(nft).aiOracleCallback{gas: gl}(requestId, output, "");
        // ORAERC7007Impl(nft).aiOracleCallback{gas: gl + 1000 + 2200 + 30_189 + 30_189}(requestId, output, "");
    }

    function getRequestGasLimit(
        uint256 requestId
    ) public returns (uint64) {
        bytes4 selector = bytes4(keccak256("requests(uint256)"));
        (bool success, bytes memory result) = aiOracle.staticcall(abi.encodeWithSelector(selector, requestId));
        require(success);
        (address account, uint256 rid, uint256 mid, bytes memory inpt, address cb, uint64 gl) =
            abi.decode(result, (address, uint256, uint256, bytes, address, uint64));
        return gl;
    }

    function decodeCIDs(
        bytes calldata data
    ) public pure returns (bytes[] memory) {
        require(data.length >= 4, "Data too short");
        uint32 count = uint32(bytes4(data[:4]));
        console2.log("count: ", count);
        bytes[] memory cids = new bytes[](count);

        uint256 offset = 4;
        for (uint32 i = 0; i < count; i++) {
            require(data.length >= offset + 4, "Invalid data length");
            uint32 cidLength = uint32(bytes4(data[offset:offset + 4]));
            offset += 4;
            require(data.length >= offset + cidLength, "Invalid CID length");

            bytes memory cidBytes = new bytes(cidLength);
            // for (uint32 j = 0; j < cidLength; j++) {
            //     cidBytes[j] = data[offset + j];
            // }

            assembly {
                calldatacopy(add(cidBytes, 32), add(data.offset, offset), cidLength)
            }
            // console2.log("cid: ", string(cidBytes));
            cids[i] = cidBytes;
            offset += cidLength;
        }
        return cids;
    }
}
