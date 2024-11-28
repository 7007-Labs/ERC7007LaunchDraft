// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {ORAERC7007Impl} from "../../src/nft/ORAERC7007Impl.sol";
import {IAIOracle} from "../../src/interfaces/IAIOracle.sol";
import {IRandOracle} from "../../src/interfaces/IRandOracle.sol";
import {MockAIOracle} from "../mocks/MockAIOracle.t.sol";
import {MockRandOracle} from "../mocks/MockRandOracle.t.sol";

contract ORAERC7007ImplTest is Test {
    ORAERC7007Impl public nft;
    MockAIOracle public mockAiOracle;
    MockRandOracle public mockRandOracle;

    address owner = makeAddr("owner");
    address defaultNFTOwner = makeAddr("defaultNFTOwner");
    address operator = makeAddr("operator");
    address user = makeAddr("user");
    address approved = makeAddr("approved");
    uint256 totalSupply = 7707;

    string name = "Test NFT";
    string symbol = "TEST";
    string description = "Test NFT Collection";
    bool nsfw = true;
    string defaultPrompt = "Test prompt";
    uint256 defaultModelId = 50;

    function setUp() public {
        mockAiOracle = new MockAIOracle();
        mockRandOracle = new MockRandOracle();

        ORAERC7007Impl impl = new ORAERC7007Impl(IAIOracle(address(mockAiOracle)), IRandOracle(address(mockRandOracle)));
        address proxy = Clones.clone(address(impl));
        nft = ORAERC7007Impl(proxy);

        bytes memory metadataInitializer = abi.encode(name, symbol, description, nsfw);

        nft.initialize(owner, defaultPrompt, metadataInitializer, defaultModelId);
    }

    function test_Initialize() public view {
        assertEq(nft.name(), name);
        assertEq(nft.symbol(), symbol);
        assertEq(nft.description(), description);
        assertEq(nft.nsfw(), nsfw);
        assertEq(nft.basePrompt(), defaultPrompt);
        assertEq(nft.modelId(), defaultModelId);
        assertEq(nft.owner(), owner);
    }

    function test_Activate() public {
        nft.activate(totalSupply, defaultNFTOwner, operator);

        assertEq(nft.totalSupply(), totalSupply);
        assertEq(nft.operator(), operator);

        // Check all tokens are owned by DEFAULT_NFT_OWNER
        for (uint256 i = 0; i < totalSupply; i++) {
            assertEq(nft.ownerOf(i), defaultNFTOwner);
        }

        assertEq(nft.balanceOf(defaultNFTOwner), totalSupply);
    }

    function test_Transfer() public {
        nft.activate(totalSupply, defaultNFTOwner, operator);

        uint256 userBalanceBefore = nft.balanceOf(user);
        uint256 defaultOwnerBalanceBefore = nft.balanceOf(defaultNFTOwner);

        vm.prank(defaultNFTOwner);
        nft.transferFrom(defaultNFTOwner, user, 0);
        assertEq(nft.ownerOf(0), user);

        uint256 userBalanceAfter = nft.balanceOf(user);
        uint256 defaultOwnerBalanceAfter = nft.balanceOf(defaultNFTOwner);

        assertEq(userBalanceAfter - userBalanceBefore, 1);
        assertEq(defaultOwnerBalanceBefore - defaultOwnerBalanceAfter, 1);
    }

    function test_TokenURI() public {
        nft.activate(totalSupply, defaultNFTOwner, operator);

        string memory uri = nft.tokenURI(0);
        assertTrue(bytes(uri).length > 0);
    }

    function test_SetDefaultRoyalty() public {
        uint96 feeNumerator = 250; // 2.5%

        vm.prank(owner);
        nft.setDefaultRoyalty(owner, feeNumerator);

        (address receiver, uint256 royaltyAmount) = nft.royaltyInfo(0, 10_000);
        assertEq(receiver, owner);
        assertEq(royaltyAmount, 250); // 2.5% of 10000
    }

    function test_Approve() public {
        nft.activate(totalSupply, defaultNFTOwner, operator);

        vm.prank(defaultNFTOwner);
        nft.approve(approved, 0);

        assertEq(nft.getApproved(0), approved);

        // Test that approved address can transfer the token
        vm.prank(approved);
        nft.transferFrom(defaultNFTOwner, user, 0);
        assertEq(nft.ownerOf(0), user);

        // Approval should be cleared after transfer
        assertEq(nft.getApproved(0), address(0));
    }

    function test_Revert_Approve_IfNotOwner() public {
        nft.activate(totalSupply, defaultNFTOwner, operator);

        vm.prank(user);
        vm.expectRevert();
        nft.approve(approved, 0);
    }

    function test_SetApprovalForAll() public {
        nft.activate(totalSupply, defaultNFTOwner, operator);

        vm.prank(defaultNFTOwner);
        nft.setApprovalForAll(approved, true);

        assertTrue(nft.isApprovedForAll(defaultNFTOwner, approved));

        // Test approved address can transfer any token
        vm.prank(approved);
        nft.transferFrom(defaultNFTOwner, user, 0);
        assertEq(nft.ownerOf(0), user);

        // Test removing approval
        vm.prank(defaultNFTOwner);
        nft.setApprovalForAll(approved, false);
        assertFalse(nft.isApprovedForAll(defaultNFTOwner, approved));

        // Test approved address can no longer transfer after approval removed
        vm.prank(approved);
        vm.expectRevert();
        nft.transferFrom(defaultNFTOwner, user, 1);
    }

    function test_Revert_SetDefaultRoyalty_IfNotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        nft.setDefaultRoyalty(user, 250);
    }

    function test_Revert_TransferFrom_IfNotOwnerOfNFT() public {
        nft.activate(totalSupply, defaultNFTOwner, operator);

        vm.prank(user);
        vm.expectRevert();
        nft.transferFrom(defaultNFTOwner, user, 0);
    }

    function test_Revert_Activate_WhenCallTwice() public {
        nft.activate(totalSupply, defaultNFTOwner, operator);

        vm.expectRevert();
        nft.activate(totalSupply, defaultNFTOwner, operator);
    }

    function test_Revert_Activate_WithZeroAddress() public {
        vm.expectRevert();
        nft.activate(totalSupply, address(0), operator);

        vm.expectRevert();
        nft.activate(totalSupply, defaultNFTOwner, address(0));
    }

    function test_Revert_Activate_WithZeroSupply() public {
        vm.expectRevert();
        nft.activate(0, defaultNFTOwner, operator);
    }

    function test_Reveal() public {
        nft.activate(totalSupply, defaultNFTOwner, operator);

        mockAiOracle.setGasPrice(1 gwei);
        mockRandOracle.setGasPrice(1 gwei);

        uint256 fee = nft.estimateRevealFee(3);
        vm.deal(operator, fee);
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 0;
        tokenIds[1] = 700;
        tokenIds[2] = 5555;
        vm.prank(operator);

        nft.reveal{value: fee}(tokenIds, address(0));

        vm.warp(block.timestamp + 1);
        mockRandOracle.invoke(1, abi.encode(block.timestamp), "");
        for (uint256 i; i < tokenIds.length; i++) {
            uint256 tokenId = tokenIds[i];
            assertNotEq(nft.seedOf(tokenId), 0);
        }

        vm.warp(block.timestamp + 3);
        mockAiOracle.invokeCallback(1, mockAiOracle.makeOutput(3));

        string memory tokenURI = nft.tokenURI(0);
        string memory expectedURI =
            "data:application/json;base64,eyJuYW1lIjogIlRlc3QgTkZUIiwgImRlc2NyaXB0aW9uIjogIlRlc3QgTkZUIENvbGxlY3Rpb24iLCAiaW1hZ2UiOiAiaXBmczovL1FtWTNHdU5jc2NtekQ2Q25WaktXZXFmU1BhVlhiMmdjazc1SFVydHE4WWYzc3UiLCAicHJvbXB0IjogIlRlc3QgcHJvbXB0IiwgImFpZ2NfdHlwZSI6ICJpbWFnZSIsICJhaWdjX2RhdGEiOiAiUW1ZM0d1TmNzY216RDZDblZqS1dlcWZTUGFWWGIyZ2NrNzVIVXJ0cThZZjNzdSIsICJwcm9vZl90eXBlIjogImZyYXVkIiwgInByb3ZpZGVyIjogIjB4NTYxNWRlYjc5OGJiM2U0ZGZhMDEzOWRmYTFiM2Q0MzNjYzIzYjcyZiIsICJtb2RlbElkIjogIjUwIn0=";
        assertEq(tokenURI, expectedURI);

        bytes memory prompt =
            abi.encodePacked('{"prompt":"', nft.basePrompt, '","seed":', Strings.toString(nft.seedOf(0)), "}");
        bool isVerified = nft.verify(prompt, nft.aigcDataOf(0), "");
        assertTrue(isVerified);
    }

    function test_RetryRequestAIOracle() public {
        nft.activate(totalSupply, defaultNFTOwner, operator);

        mockAiOracle.setGasPrice(1 gwei);
        mockRandOracle.setGasPrice(1 gwei);

        uint256 fee = nft.estimateRevealFee(3);
        vm.deal(operator, fee);
        uint256[] memory tokenIds = new uint256[](3);
        tokenIds[0] = 0;
        tokenIds[1] = 700;
        tokenIds[2] = 5555;
        vm.prank(operator);

        nft.reveal{value: fee}(tokenIds, address(0));

        bytes32 requestId = keccak256(abi.encodePacked(tokenIds));

        vm.warp(block.timestamp + 2);
        // the gasPrice will be very high, making it impossible to call the aiOracle
        mockAiOracle.setGasPrice(10 gwei);
        vm.expectEmit();
        emit ORAERC7007Impl.NotRequestAIOracle(requestId, address(0));
        mockRandOracle.invoke(1, abi.encode(block.timestamp), "");

        vm.warp(block.timestamp + 2);
        vm.expectRevert(ORAERC7007Impl.InsufficientBalance.selector);
        nft.retryRequestAIOracle(requestId, address(0));

        vm.warp(block.timestamp + 2);
        mockAiOracle.setGasPrice(1 gwei);
        nft.retryRequestAIOracle(requestId, address(0));
        assertEq(nft.tokenIdToAiOracleRequestId(0), 1);

        mockAiOracle.invokeCallback(1, mockAiOracle.makeOutput(3));
    }
}
