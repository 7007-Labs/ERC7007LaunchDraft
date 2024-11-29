// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {BitMaps} from "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import {LibBit} from "./LibBit.sol";

library BitMapHelpers {
    /// @dev Selects `num` random unset bits in `[0..range)`
    function randomSelectUnset(
        BitMaps.BitMap storage bitmap,
        uint256 num,
        uint256 range
    ) internal view returns (uint256[] memory indexes) {
        indexes = new uint256[](num);

        uint256 bucketCount = (range + 255) >> 8;
        uint256 startBucket = uint256(blockhash(block.number)) % bucketCount;
        uint256 count = 0;

        uint256 lastBucketBits = range & 0xff;
        uint256 lastBucketMask = lastBucketBits > 0 ? (1 << lastBucketBits) - 1 : type(uint256).max;

        for (uint256 i; i < bucketCount && count < num; i++) {
            uint256 bucket = (startBucket + i) % bucketCount;
            uint256 data = bitmap._data[bucket];

            uint256 mask = bucket == bucketCount - 1 ? lastBucketMask : type(uint256).max;

            uint256 availableIndexes = (~data) & mask;
            while (availableIndexes != 0 && count < num) {
                uint256 index = (bucket << 8) | LibBit.ffs(availableIndexes);
                indexes[count] = index;
                count++;
                availableIndexes &= (availableIndexes - 1);
            }
        }
        assembly {
            mstore(indexes, count)
        }
    }

    function setBatchCalldata(BitMaps.BitMap storage bitmap, uint256[] calldata indexes) internal {
        uint256 len = indexes.length;
        for (uint256 i; i < len;) {
            uint256 index = indexes[i];
            uint256 bucket = index >> 8;
            uint256 pos = index & 0xff;

            uint256 mask = 1 << pos;
            while (i + 1 < len) {
                uint256 nextIndex = indexes[i + 1];
                uint256 nextBucket = nextIndex >> 8;
                if (nextBucket != bucket) break;

                mask |= 1 << (nextIndex & 0xff);
                i++;
            }
            bitmap._data[bucket] |= mask;
            i++;
        }
    }
}
