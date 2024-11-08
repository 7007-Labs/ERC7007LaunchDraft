// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console2} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ORAERC7007Impl} from "../../src/nft/ORAERC7007Impl.sol";
import {IAIOracle} from "../../src/interfaces/IAIOracle.sol";

/*
contract MockAIOracle is IAIOracle {
    uint256 public constant MOCK_FEE = 0.01 ether;

    function estimateFee(uint256, uint256) external pure returns (uint256) {
        return MOCK_FEE;
    }

    function estimateFeeBatch(uint256, uint256, uint256) external pure returns (uint256) {
        return MOCK_FEE;
    }

    function requestCallback(
        uint256,
        bytes calldata,
        address,
        uint64,
        bytes calldata
    ) external payable returns (uint256) {
        require(msg.value >= MOCK_FEE, "Insufficient fee");
        return 1; // Mock request ID
    }

    function requestCallback(
        uint256 modelId,
        bytes memory input,
        address callbackContract,
        uint64 gasLimit,
        bytes memory callbackData,
        DA inputDA,
        DA outputDA
    ) external payable returns (uint256) {
        return 1;
    }

    function requestBatchInference(
        uint256 batchSize,
        uint256 modelId,
        bytes memory input,
        address callbackContract,
        uint64 gasLimit,
        bytes memory callbackData,
        DA inputDA,
        DA outputDA
    ) external payable returns (uint256) {
        // require(msg.value >= MOCK_FEE, "Insufficient fee");
        return 1; // Mock request ID
    }

    function isFinalized(
        uint256
    ) external pure returns (bool) {
        return true; // Always return true for the mock
    }
}

contract ORAERC7007ImplTest is Test {
    ORAERC7007Impl public nft;
    address public owner;
    address public defaultNFTOwner;
    address public user1;
    address public user2;
    address mockAIOracle;
    string name = "Test NFT";
    string symbol = "TNFT";
    string basePrompt = "Test Prompt";
    uint256 modelId = 50;
    bool nsfw = false;
    uint256 public constant TOTAL_SUPPLY = 7007;

    function setUp() public {
        defaultNFTOwner = makeAddr("defaultNFTOwner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy mock AIOracle
        mockAIOracle = address(new MockAIOracle());

        // vm.mockCall(mockAIOracle, abi.encodeWithSelector(IAIOracle.isFinalized.selector), abi.encode(true));

        // Deploy NFT contract
        ORAERC7007Impl nftImpl = new ORAERC7007Impl(IAIOracle(mockAIOracle));

        ERC1967Proxy proxy = new ERC1967Proxy(address(nftImpl), "");
        nft = ORAERC7007Impl(address(proxy));
        nft.initialize(name, symbol, basePrompt, address(this), nsfw, modelId);
    }

    function test_Initialize() public {
        assertEq(nft.name(), name);
        assertEq(nft.symbol(), symbol);
        assertEq(nft.owner(), address(this));
    }

    function test_Initialize_Twice() public {
        vm.expectRevert();
        nft.initialize("Test NFT 2", "TNFT2", "Test Prompt 2", address(2), true, 50);
    }

    function test_mintAll() public {
        nft.mintAll(defaultNFTOwner, TOTAL_SUPPLY);
        assertEq(nft.balanceOf(defaultNFTOwner), TOTAL_SUPPLY);
        // Check initial ownership
        for (uint256 i = 0; i < TOTAL_SUPPLY; i++) {
            assertEq(nft.ownerOf(i), defaultNFTOwner);
        }
    }

    function test_Transfer() public {
        nft.mintAll(defaultNFTOwner, TOTAL_SUPPLY);
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
        nft.mintAll(defaultNFTOwner, TOTAL_SUPPLY);
        vm.expectRevert();
        nft.transferFrom(defaultNFTOwner, user1, 0);
    }

    function generateBytes(
        uint256 length
    ) public pure returns (bytes memory) {
        bytes memory result = new bytes(length);

        for (uint256 i = 0; i < length; i++) {
            // 这里使用0x61 ("a")作为示例，你可以修改为其他值
            result[i] = 0x61;
        }

        return result;
    }

    function test_addAigcData() public {
        bytes memory b22 = generateBytes(22);
        bytes memory b32 = generateBytes(32);
        bytes memory b46 = generateBytes(46);
        bytes memory b64 = generateBytes(64);
        bytes memory b256 = generateBytes(256);
        uint256 s = gasleft();
        vm.prank(address(nft));
        nft.addAigcData(1, "a big dog", b32, "");
        uint256 s1 = gasleft();
        console2.log("cost1: ", s - s1);
        vm.prank(address(nft));
        nft.addAigcData(2, b22, b46, "");

        uint256 s2 = gasleft();
        console2.log("cost2: ", s1 - s2);
        vm.prank(address(nft));
        nft.addAigcData(3, b256, b46, "");
        uint256 s3 = gasleft();
        console2.log("cost3: ", s2 - s3);
        uint256 t = s - gasleft();
        console2.log("cost: ", t);
    }

    function test_update() public {
        bytes memory b22 = generateBytes(22);
        bytes memory b32 = generateBytes(32);
        bytes memory b46 = generateBytes(46);
        bytes memory b64 = generateBytes(64);
        bytes memory b256 = generateBytes(256);
        uint256 s = gasleft();
        vm.prank(address(nft));
        nft.update("a big dog", b32);
        uint256 s1 = gasleft();
        console2.log("cost1: ", s - s1);
        vm.prank(address(nft));
        nft.update(b22, b46);

        uint256 s2 = gasleft();
        console2.log("cost2: ", s1 - s2);
        vm.prank(address(nft));
        nft.update(b256, b46);
        uint256 s3 = gasleft();
        console2.log("cost3: ", s2 - s3);
        uint256 t = s - gasleft();
        console2.log("cost: ", t);
    }

    function generateOutput(
        uint32 num
    ) public pure returns (bytes memory) {
        bytes memory pattern = bytes("\x00\x00\x00.QmY3GuNcscmzD6CnVjKWeqfSPaVXb2gck75HUrtq8Yf3su");
        uint256 patternSize = pattern.length;
        uint256 totalLength = 4 + num * patternSize;
        bytes memory result = new bytes(totalLength);
        for (uint256 i = 0; i < 4; i++) {
            result[i] = bytes1(uint8(num >> (8 * (3 - i))));
        }
        for (uint256 i = 0; i < num; i++) {
            for (uint256 j = 0; j < patternSize; j++) {
                result[4 + i * patternSize + j] = pattern[j];
            }
        }
        return result;
    }

    function test_callback() public {
        bytes memory output = bytes(
            "\x00\x00\x00\x02\x00\x00\x00.QmY3GuNcscmzD6CnVjKWeqfSPaVXb2gck75HUrtq8Yf3su\x00\x00\x00.QmXwcj4rYofnQuZpjAsUmqPaDEkaJ7ZhwuLCRVgCarRSPN"
        );
        uint32 n = 2;
        bytes memory o2 = generateOutput(n);
        nft.mintAll(address(this), 7007);
        uint256[] memory tokenIds = new uint256[](n);
        for (uint256 i = 0; i < n; i++) {
            tokenIds[i] = i;
        }
        nft.reveal(tokenIds);

        // uint256 gasLimt = 17_737 + (14_766 + 29_756) * n;
        uint256 gasLimt = 17_737 + (14_766 + 29_756) * n;
        console2.log("gaslimit: ", gasLimt);

        vm.prank(mockAIOracle);
        uint256 s1 = gasleft();
        nft.aiOracleCallback{gas: gasLimt}(1, o2, "");
        uint256 s2 = gasleft();
        console2.log("cost: ", s1 - s2);
        console2.log("delta: ", gasLimt - (s1 - s2));
        console2.log("rate: ", (gasLimt - (s1 - s2)) * 100 / (s1 - s2));
        // console2.log("out: ", string(o2));
    }
}
*/
