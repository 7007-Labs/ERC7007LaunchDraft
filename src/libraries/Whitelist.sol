// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

abstract contract Whitelist {
    bytes32 public whitelistMerkleRoot = bytes32(0);

    function _setWhitelistMerkleRoot(
        bytes32 root
    ) internal {
        whitelistMerkleRoot = root;
    }

    function verifyWhitelistAddress(address addr, bytes32[] calldata proof) internal view returns (bool) {
        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(addr))));
        return MerkleProof.verifyCalldata(proof, whitelistMerkleRoot, leaf);
    }
}
