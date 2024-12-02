import sys
from multiproof import StandardMerkleTree

if len(sys.argv) != 2:
    print("Usage: python merkleProof.py <filepath>")
    exit(1)

filepath = sys.argv[1]

with open(filepath, "r") as fp:
    addresses = fp.read().splitlines()
addresses = [x.strip() for x in addresses]

tree = StandardMerkleTree.of(
    [
        [
            x,
        ]
        for x in addresses
    ],
    [
        "address",
    ],
)

print("merkleRoot: ", tree.root)

for i, leaf in enumerate(tree.values):
    proof = tree.get_proof(i)
    print(leaf.value[0], proof)
