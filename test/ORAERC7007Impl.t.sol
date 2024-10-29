// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ORAERC7007Impl} from "../src/nft/ORAERC7007Impl.sol";
import {IAIOracle} from "../src/interfaces/IAIOracle.sol";

contract ORAERC7007ImplTest is Test {
    ORAERC7007Impl public nft;
    address public owner;
    address public defaultNFTOwner;
    address public user1;
    address public user2;
    address mockAIOracle = makeAddr("mockAIOracle");

    uint256 public constant TOTAL_SUPPLY = 7007;

    function setUp() public {
        owner = makeAddr("owner");
        defaultNFTOwner = makeAddr("defaultNFTOwner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy mock AIOracle

        vm.mockCall(mockAIOracle, abi.encodeWithSelector(IAIOracle.isFinalized.selector), abi.encode(true));

        // Deploy NFT contract
        ORAERC7007Impl nftImpl = new ORAERC7007Impl(IAIOracle(mockAIOracle));

        ERC1967Proxy proxy = new ERC1967Proxy(address(nftImpl), "");
        nft = ORAERC7007Impl(address(proxy));
    }

    function test_Initialize() public {
        string memory name = "Test NFT";
        string memory symbol = "TNFT";
        string memory basePrompt = "Test Prompt";
        uint256 modelId = 50;
        bool nsfw = false;
        nft.initialize(name, symbol, basePrompt, owner, TOTAL_SUPPLY, defaultNFTOwner, nsfw, modelId);

        assertEq(nft.name(), name);
        assertEq(nft.symbol(), symbol);
        assertEq(nft.owner(), owner);
        assertEq(nft.totalSupply(), TOTAL_SUPPLY);
    }

    function test_Initialize_RevertWhenCalledTwice() public {
        nft.initialize("Test NFT", "TNFT", "Test Prompt", owner, TOTAL_SUPPLY, defaultNFTOwner, false, 1);

        vm.expectRevert();
        nft.initialize("Test NFT 2", "TNFT2", "Test Prompt 2", owner, TOTAL_SUPPLY, defaultNFTOwner, false, 1);
    }

    function test_DefaultOwnership() public {
        nft.initialize("Test NFT", "TNFT", "Test Prompt", owner, TOTAL_SUPPLY, defaultNFTOwner, false, 1);

        assertEq(nft.balanceOf(defaultNFTOwner), TOTAL_SUPPLY);
        // Check initial ownership
        for (uint256 i = 0; i < TOTAL_SUPPLY; i++) {
            assertEq(nft.ownerOf(i), defaultNFTOwner);
        }
    }

    function test_Transfer() public {
        nft.initialize("Test NFT", "TNFT", "Test Prompt", owner, TOTAL_SUPPLY, defaultNFTOwner, false, 1);

        // Transfer token from defaultNFTOwner to user1
        // assertEq(nft.ownerOf(0), defaultNFTOwner);
        vm.prank(defaultNFTOwner);
        nft.transferFrom(defaultNFTOwner, user1, 0);
        assertEq(nft.ownerOf(0), user1);
        assertEq(nft.balanceOf(user1), 1);
        assertEq(nft.balanceOf(defaultNFTOwner), TOTAL_SUPPLY - 1);
        // Transfer token from user1 to user2
        vm.prank(user1);
        nft.transferFrom(user1, user2, 0);
        assertEq(nft.ownerOf(0), user2);
        assertEq(nft.balanceOf(user2), 1);
        assertEq(nft.balanceOf(user1), 0);
    }

    function test_Transfer_beforeMint() public {
        vm.prank(defaultNFTOwner);
        vm.expectRevert();
        nft.transferFrom(defaultNFTOwner, user1, 0);
    }

    function test_Transfer_WrongOwner() public {
        nft.initialize("Test NFT", "TNFT", "Test Prompt", owner, TOTAL_SUPPLY, defaultNFTOwner, false, 1);
        vm.expectRevert();
        nft.transferFrom(defaultNFTOwner, user1, 0);
    }
}
