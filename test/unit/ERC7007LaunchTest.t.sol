// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {ERC7007Launch} from "../../src/ERC7007Launch.sol";
import {PairType} from "../../src/enums/PairType.sol";
import {MockPair} from "../mocks/MockPair.t.sol";
import {MockAIOracle} from "../mocks/MockAIOracle.t.sol";
import {MockRandOracle} from "../mocks/MockRandOracle.t.sol";
import {MockCurve} from "../mocks/MockCurve.t.sol";

contract ERC7007LaunchTest is Test {
    ERC7007Launch public launch;
    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    address public nftFactory = makeAddr("nftFactory");
    address public pairFactory = makeAddr("pairFactory");
    address public pair;

    function setUp() public {
        pair = address(new MockPair());
        ERC7007Launch impl = new ERC7007Launch(nftFactory, pairFactory);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        launch = ERC7007Launch(address(proxy));
        launch.initialize(owner);
    }

    function test_InitialState() public view {
        assertTrue(launch.isEnableWhitelist());
        assertFalse(launch.paused());
        assertEq(launch.owner(), owner);
    }

    function test_Revert_SetWhitelistMerkleRoot_OnlyOwner() public {
        vm.prank(user);
        vm.expectRevert();
        launch.setWhitelistMerkleRoot(bytes32(0));
    }

    function test_DisableWhitelist() public {
        vm.prank(owner);
        launch.disableWhitelist();
        assertFalse(launch.isEnableWhitelist());
    }

    function test_Revert_DisableWhitelist_OnlyOwner() public {
        vm.prank(user);
        vm.expectRevert();
        launch.disableWhitelist();
    }

    function test_EnableWhitelist() public {
        vm.startPrank(owner);
        launch.disableWhitelist();
        launch.enableWhitelist();
        vm.stopPrank();
        assertTrue(launch.isEnableWhitelist());
    }

    function test_Revert_EnableWhitelist_OnlyOwner() public {
        vm.prank(user);
        vm.expectRevert();
        launch.enableWhitelist();
    }

    function test_Pause() public {
        vm.prank(owner);
        launch.pause();
        assertTrue(launch.paused());
    }

    function test_Revert_Pause_OnlyOwner() public {
        vm.prank(user);
        vm.expectRevert();
        launch.pause();
    }

    function test_Unpause() public {
        vm.startPrank(owner);
        launch.pause();
        launch.unpause();
        vm.stopPrank();
        assertFalse(launch.paused());
    }

    function test_Revert_Unpause_OnlyOwner() public {
        vm.prank(owner);
        launch.pause();

        vm.prank(user);
        vm.expectRevert();
        launch.unpause();
    }

    function test_FunctionsPausedBehavior() public {
        vm.prank(owner);
        launch.pause();

        ERC7007Launch.LaunchParams memory params;
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        launch.launch(params, new bytes32[](0));

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        launch.purchasePresaleNFTs(address(0), 1, 1 ether, address(0), new bytes32[](0), new bytes32[](0));

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        launch.swapTokenForNFTs(address(0), 1, 1 ether, address(0), new bytes32[](0));

        uint256[] memory tokenIds = new uint256[](1);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        launch.swapTokenForSpecificNFTs(address(0), tokenIds, 1, 1 ether, address(0), new bytes32[](0));

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        launch.swapNFTsForToken(address(0), tokenIds, 1 ether, payable(address(0)), new bytes32[](0));
    }

    function test_WhitelistVerification() public {
        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = bytes32(0);

        ERC7007Launch.LaunchParams memory params;
        vm.expectRevert(ERC7007Launch.CallerNotWhitelisted.selector);
        launch.launch(params, invalidProof);

        vm.expectRevert(ERC7007Launch.CallerNotWhitelisted.selector);
        launch.purchasePresaleNFTs(pair, 1, 1 ether, address(0), invalidProof, invalidProof);

        vm.expectRevert(ERC7007Launch.CallerNotWhitelisted.selector);
        launch.swapTokenForNFTs(pair, 1, 1 ether, address(0), invalidProof);

        uint256[] memory tokenIds = new uint256[](1);
        vm.expectRevert(ERC7007Launch.CallerNotWhitelisted.selector);
        launch.swapTokenForSpecificNFTs(pair, tokenIds, 1, 1 ether, address(0), invalidProof);

        vm.expectRevert(ERC7007Launch.CallerNotWhitelisted.selector);
        launch.swapNFTsForToken(pair, tokenIds, 1 ether, payable(address(0)), invalidProof);
    }

    function test_WhitelistBypassWhenDisabled() public {
        vm.prank(owner);
        launch.disableWhitelist();

        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = bytes32(0);

        launch.purchasePresaleNFTs(pair, 1, 1 ether, address(0), invalidProof, invalidProof);

        launch.swapTokenForNFTs(pair, 1, 1 ether, address(0), invalidProof);

        uint256[] memory tokenIds = new uint256[](1);
        launch.swapTokenForSpecificNFTs(pair, tokenIds, 1, 1 ether, address(0), invalidProof);

        launch.swapNFTsForToken(pair, tokenIds, 1 ether, payable(address(0)), invalidProof);
    }

    function test_WhitelistByPassWithProof() public {
        bytes32 root = 0xfeddcd9ebbb017ef7aedb6d5af6646b5cf1af84bfd1fc0bda8c59d068c3b12be;
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = 0x4e2ef3f4d279d23ce0933035d8c8fb3ce41acb03aa29a326c527a6c76b912f6e; // proof for makeAddr("user")

        vm.prank(owner);
        launch.setWhitelistMerkleRoot(root);

        vm.startPrank(user);
        launch.purchasePresaleNFTs(pair, 1, 1 ether, address(0), new bytes32[](0), proof);

        launch.swapTokenForNFTs(pair, 1, 1 ether, address(0), proof);

        uint256[] memory tokenIds = new uint256[](1);
        launch.swapTokenForSpecificNFTs(pair, tokenIds, 1, 1 ether, address(0), proof);

        launch.swapNFTsForToken(pair, tokenIds, 1 ether, payable(address(0)), proof);
        vm.stopPrank();
    }

    function test_GetInitialBuyQuote() public {
        MockAIOracle aiOracle = new MockAIOracle();
        MockRandOracle randOracle = new MockRandOracle();
        MockCurve curve = new MockCurve(20);

        ERC7007Launch.LaunchParams memory params;
        params.initialBuyNum = 10;
        params.bondingCurve = address(curve);
        params.prompt = "test prompt";
        params.providerParams = abi.encode(50);
        vm.mockCall(address(aiOracle), abi.encodeWithSelector(aiOracle.estimateFeeBatch.selector), abi.encode(300));
        vm.mockCall(address(randOracle), abi.encodeWithSelector(randOracle.estimateFee.selector), abi.encode(30));

        uint256 fee = launch.estimateLaunchFee(params, address(aiOracle), address(randOracle));
        uint256 expectedFee = 10 * 20 + 300 + 30 + 4;
        assertEq(fee, expectedFee);

        params.presaleEnd = uint64(block.timestamp + 1 days);
        uint256 feeWithPresale = launch.estimateLaunchFee(params, address(aiOracle), address(randOracle));
        assertEq(feeWithPresale, 0);
    }
}
