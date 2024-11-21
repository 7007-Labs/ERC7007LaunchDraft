// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

import {RoyaltyExecutor} from "../../src/RoyaltyExecutor.sol";

contract MockNFT is IERC2981 {
    address public royaltyRecipient;
    uint256 public royaltyBps;

    constructor(address _recipient, uint256 _royaltyBps) {
        royaltyRecipient = _recipient;
        royaltyBps = _royaltyBps;
    }

    function supportsInterface(
        bytes4 interfaceId
    ) external pure returns (bool) {
        return interfaceId == type(IERC2981).interfaceId;
    }

    function royaltyInfo(uint256, uint256 salePrice) external view returns (address receiver, uint256 royaltyAmount_) {
        return (royaltyRecipient, (royaltyBps * salePrice) / 10_000);
    }
}

contract MockNFTWithoutERC2981 {}

contract RoyaltyExecutorTest is Test {
    RoyaltyExecutor public royaltyExecutor;
    address public pair = makeAddr("pair");
    address public owner = makeAddr("owner");
    address public user = makeAddr("user");

    function setUp() public {
        RoyaltyExecutor royaltyExecutorImpl = new RoyaltyExecutor();
        ERC1967Proxy proxy = new ERC1967Proxy(address(royaltyExecutorImpl), "");
        royaltyExecutor = RoyaltyExecutor(address(proxy));
        royaltyExecutor.initialize(owner);
    }

    function test_Initialize() public view {
        assertEq(royaltyExecutor.owner(), owner);
    }

    function test_Revert_Initialize_IfHasInitialized() public {
        vm.expectRevert();
        royaltyExecutor.initialize(vm.addr(2));
    }

    function test_CalculateRoyaltyWithDisabledPair() public {
        address nft = address(new MockNFT(vm.addr(1), 100));

        vm.mockCall(pair, abi.encodeWithSignature("nft()"), abi.encode(nft));
        (address payable[] memory recipients, uint256[] memory amounts, uint256 royaltyAmount) =
            royaltyExecutor.calculateRoyalty(pair, 1, 1 ether);

        assertEq(recipients.length, 0);
        assertEq(amounts.length, 0);
        assertEq(royaltyAmount, 0);
    }

    function test_CalculateRoyaltyWithEnabledPair() public {
        vm.prank(owner);
        royaltyExecutor.setPairRoyaltyStatus(address(pair), true);
        address recipient = vm.addr(1);
        address nft = address(new MockNFT(recipient, 500));

        vm.mockCall(pair, abi.encodeWithSignature("nft()"), abi.encode(nft));
        (address payable[] memory recipients, uint256[] memory amounts, uint256 royaltyAmount) =
            royaltyExecutor.calculateRoyalty(pair, 1, 1 ether);

        assertEq(recipients.length, 1);
        assertEq(amounts.length, 1);
        assertEq(recipients[0], payable(recipient));
        assertEq(amounts[0], 0.05 ether); // 5% of 1 ether
        assertEq(royaltyAmount, 0.05 ether);
    }

    function test_CalculateRoyalty_IfNFTNotSupportERC2981() public {
        vm.prank(owner);
        royaltyExecutor.setPairRoyaltyStatus(address(pair), true);

        address nft = address(new MockNFTWithoutERC2981());
        vm.mockCall(pair, abi.encodeWithSignature("nft()"), abi.encode(nft));

        (address payable[] memory recipients, uint256[] memory amounts, uint256 royaltyAmount) =
            royaltyExecutor.calculateRoyalty(pair, 1, 1 ether);

        assertEq(recipients.length, 0);
        assertEq(amounts.length, 0);
        assertEq(royaltyAmount, 0);
    }

    function test_SetPairRoyaltyStatus() public {
        vm.prank(owner);
        royaltyExecutor.setPairRoyaltyStatus(pair, true);

        assertTrue(royaltyExecutor.pairRoyaltyAllowed(pair));
    }

    function test_Revert_SetPairRoyaltyStatus_NotOwner() public {
        vm.prank(user);
        vm.expectRevert();
        royaltyExecutor.setPairRoyaltyStatus(pair, true);
    }

    function test_SetBatchPairRoyaltyStatus() public {
        address[] memory pairs = new address[](2);
        pairs[0] = pair;
        pairs[1] = makeAddr("pair2");

        bool[] memory isAllowed = new bool[](2);
        isAllowed[0] = true;
        isAllowed[1] = false;

        vm.prank(owner);
        royaltyExecutor.setBatchPairRoyaltyStatus(pairs, isAllowed);

        assertTrue(royaltyExecutor.pairRoyaltyAllowed(pairs[0]));
        assertFalse(royaltyExecutor.pairRoyaltyAllowed(pairs[1]));
    }

    function test_SetBatchPairRoyaltyStatus_OnlyOwner() public {
        address[] memory pairs = new address[](1);
        bool[] memory isAllowed = new bool[](1);

        vm.prank(user);
        vm.expectRevert();
        royaltyExecutor.setBatchPairRoyaltyStatus(pairs, isAllowed);
    }

    function test_AuthorizeUpgrade() public {
        address newImplementation = address(new RoyaltyExecutor());

        vm.prank(owner);
        royaltyExecutor.upgradeToAndCall(newImplementation, "");
    }

    function test_Revert_AuthorizeUpgrade_NotOwner() public {
        address newImplementation = address(new RoyaltyExecutor());

        vm.prank(user);
        vm.expectRevert();
        royaltyExecutor.upgradeToAndCall(newImplementation, "");
    }
}
