// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockORAERC7007 is ERC721 {
    uint256 revealFeePerNFT;

    constructor(string memory name_, string memory symbol_, uint256 _revealFeePerNFT) ERC721(name_, symbol_) {
        revealFeePerNFT = _revealFeePerNFT;
    }

    function mint(address to, uint256 tokenId) external {
        _mint(to, tokenId);
    }

    function batchMint(address to, uint256 start, uint256 end) external {
        for (uint256 i = start; i < end; i++) {
            _mint(to, i);
        }
    }

    function estimateRevealFee(
        uint256 numItems
    ) public view returns (uint256) {
        return numItems * revealFeePerNFT;
    }

    function activate(uint256 _totalSupply, address _defaultNFTOwner, address _operator) external {}

    function reveal(uint256[] calldata tokenIds, address /*oraOracleDelegateCaller*/ ) external payable {
        uint256 fee = estimateRevealFee(tokenIds.length);
        require(msg.value >= fee, "Insufficient Fee");
    }
}
