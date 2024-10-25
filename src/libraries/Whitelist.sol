// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

abstract contract Whitelist {
    bytes32 public whitelistMerkleRoot = 0x0000000000000000000000000000000000000000000000000000000000000000;

    function setWhitelistMerkleRoot(bytes32 root) external {
        whitelistMerkleRoot = root;
    }

    function verifyWhitelistAddress(address addr, bytes32[] calldata proof) private view returns (bool) {
        bytes32 leaf = keccak256(abi.encodePacked(addr));
        return MerkleProof.verify(proof, whitelistMerkleRoot, leaf);
    }
}
