// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console} from "forge-std/Test.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {ICurve} from "../../src/interfaces/ICurve.sol";
import {IPair} from "../../src/interfaces/IPair.sol";
import {ERC7007Launch} from "../../src/ERC7007Launch.sol";
import {IntegrationBase} from "./IntegrationBase.t.sol";
import {MockAIOracle} from "../mocks/MockAIOracle.t.sol";
import {MockRandOracle} from "../mocks/MockRandOracle.t.sol";
import {Solarray} from "../utils/Solarray.sol";

contract Integration_Local is IntegrationBase {
    function testFuzz_Launch_WithPresale(
        uint24 _random
    ) public {
        _configRand(_random);

        vm.prank(admin);
        erc7007LaunchProxy.setWhitelistMerkleRoot(usersMerkleRoot);

        ERC7007Launch.LaunchParams memory params;
        uint256 promptIndex = _randUint(0, 3);
        string memory prompt = prompts[promptIndex];
        params.prompt = prompt;
        bool nsfw = _randBool();
        params.metadataInitializer = abi.encode("TEST NFT", "TNFT", "erc7007 nft description", nsfw);
        params.provider = address(aiOracle);
        params.providerParams = abi.encode(50);
        params.bondingCurve = bondingCurves[0].addr;

        params.presaleMaxNum = uint32(_randUint(1, 7006));
        uint256 totalAmount = ICurve(bondingCurves[0].addr).getBuyPrice(0, uint256(params.presaleMaxNum));
        params.presalePrice = uint96((totalAmount + uint256(params.presaleMaxNum) - 1) / uint256(params.presaleMaxNum));
        params.presaleEnd = uint64(block.timestamp + 2 days);
        params.presaleMerkleRoot = usersMerkleRoot;

        vm.prank(user1);
        address pair = erc7007LaunchProxy.launch(params, user1Proof);
        address nft = IPair(pair).nft();
        assertEq(IPair(pair).owner(), user1);

        uint256 amount;
        vm.deal(user2, 1 ether);
        vm.startPrank(user2);
        (amount,,) = IPair(pair).getPresaleQuote(0, 1);
        erc7007LaunchProxy.purchasePresaleNFTs{value: amount + 123}(pair, 1, 1 ether, user2, user2Proof, user2Proof);
        vm.stopPrank();

        vm.warp(block.timestamp + 3 days);

        uint256 nftNum = _randUint(2, 100);
        (amount,,) = IPair(pair).getBuyNFTQuote(0, nftNum, false);
        vm.prank(user2);
        erc7007LaunchProxy.swapTokenForNFTs{value: amount}(pair, nftNum, amount, user2, user2Proof);

        uint256[] memory tokenIds = new uint256[](nftNum);
        uint256 count = 0;
        for (uint256 i; i < nftNum; i++) {
            if (_randBool()) {
                tokenIds[count] = i;
                count++;
            }
        }
        if (count == 0) {
            tokenIds[count] = 0;
            count++;
        }
        assembly {
            mstore(tokenIds, count)
        }

        vm.prank(user2);
        IERC721(nft).setApprovalForAll(pair, true);

        (amount,) = IPair(pair).getSellNFTQuote(0, tokenIds.length);
        vm.prank(user2);
        erc7007LaunchProxy.swapNFTsForToken(pair, tokenIds, amount, payable(user2), user2Proof);

        (amount,,) = IPair(pair).getBuyNFTQuote(0, tokenIds.length, true);
        vm.deal(user3, 1 ether);

        vm.prank(user3);
        erc7007LaunchProxy.swapTokenForSpecificNFTs{value: amount}(
            pair, tokenIds, tokenIds.length, amount, user3, user3Proof
        );
        uint256 totalSupply = 7007 - IERC721(nft).balanceOf(pair);
        uint256 totalPrice = ICurve(bondingCurves[0].addr).getBuyPrice(0, totalSupply);
        assertEq(pair.balance >= totalPrice, true);

        _invokeRandOracle();
        _invokeAIOracle();
    }

    function testFuzz_Launch_WithoutPresale(
        uint24 _random
    ) public {
        _configRand(_random);

        vm.prank(admin);
        erc7007LaunchProxy.setWhitelistMerkleRoot(usersMerkleRoot);

        ERC7007Launch.LaunchParams memory params;
        uint256 promptIndex = _randUint(0, 3);
        string memory prompt = prompts[promptIndex];
        params.prompt = prompt;
        bool nsfw = _randBool();
        params.metadataInitializer = abi.encode("TEST NFT", "TNFT", "erc7007 nft description", nsfw);
        params.provider = address(aiOracle);
        params.providerParams = abi.encode(50);
        params.bondingCurve = bondingCurves[0].addr;
        params.initialBuyNum = _randUint(1, 300);

        uint256 amount;
        amount = erc7007LaunchProxy.estimateLaunchFee(params, aiOracle, randOracle);

        vm.deal(user1, 1 ether);
        vm.prank(user1);
        address pair = erc7007LaunchProxy.launch{value: amount}(params, user1Proof);
        address nft = IPair(pair).nft();
        assertEq(IPair(pair).owner(), user1);

        uint256 nftNum = _randUint(2, 100);
        vm.deal(user2, 1 ether);
        (amount,,) = IPair(pair).getBuyNFTQuote(0, nftNum, false);
        vm.prank(user2);
        erc7007LaunchProxy.swapTokenForNFTs{value: amount}(pair, nftNum, amount, user2, user2Proof);

        uint256[] memory tokenIds = new uint256[](nftNum);
        uint256 startTokenId = params.initialBuyNum;
        uint256 count = 0;
        for (uint256 i = startTokenId; i < nftNum; i++) {
            if (_randBool()) {
                tokenIds[count] = i;
                count++;
            }
        }
        if (count == 0) {
            tokenIds[count] = startTokenId;
            count++;
        }
        assembly {
            mstore(tokenIds, count)
        }

        vm.prank(user2);
        IERC721(nft).setApprovalForAll(pair, true);

        (amount,) = IPair(pair).getSellNFTQuote(0, tokenIds.length);
        vm.prank(user2);
        erc7007LaunchProxy.swapNFTsForToken(pair, tokenIds, amount, payable(user2), user2Proof);

        (amount,,) = IPair(pair).getBuyNFTQuote(0, tokenIds.length, true);
        vm.deal(user3, 1 ether);

        vm.prank(user3);
        erc7007LaunchProxy.swapTokenForSpecificNFTs{value: amount}(
            pair, tokenIds, tokenIds.length, amount, user3, user3Proof
        );

        uint256 totalSupply = 7007 - IERC721(nft).balanceOf(pair);
        uint256 totalPrice = ICurve(bondingCurves[0].addr).getBuyPrice(0, totalSupply);

        uint256 percent = (totalPrice - pair.balance) * 10_000 / pair.balance;
        assertEq(percent <= 1, true);

        _invokeRandOracle();
        _invokeAIOracle();
    }

    function _invokeRandOracle() internal {
        uint256 count = MockRandOracle(randOracle).latestRequestId();
        for (uint256 i = 1; i <= count; i++) {
            uint256 seed = _randUint(1, type(uint128).max);
            MockRandOracle(randOracle).invoke(i, abi.encodePacked(seed), "");
        }
    }

    function _invokeAIOracle() internal {
        uint256 randOracleCount = MockRandOracle(randOracle).latestRequestId();
        uint256 count = MockAIOracle(aiOracle).latestRequestId();
        require(randOracleCount == count, "oracle request num is wrong");
        for (uint256 i = 1; i <= count; i++) {
            bytes memory output = MockAIOracle(aiOracle).makeRequestOutput(i);
            MockAIOracle(aiOracle).invokeCallback(i, output);
        }
    }
}
