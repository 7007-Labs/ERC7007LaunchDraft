// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

library ORAUtils {
    function buildPrompt(string memory prompt, uint256 seed) public pure returns (bytes memory) {
        return abi.encodePacked('{"prompt":"', prompt, '","seed":', Strings.toString(seed), "}");
    }

    function decodeCIDs(
        bytes calldata data
    ) public pure returns (bytes[] memory) {
        require(data.length >= 4, "Data too short");
        uint32 count = uint32(bytes4(data[:4]));
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
            cids[i] = cidBytes;
            offset += cidLength;
        }
        return cids;
    }
}
