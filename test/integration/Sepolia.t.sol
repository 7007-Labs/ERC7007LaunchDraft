// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {console} from "forge-std/Test.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {ICurve} from "../../src/interfaces/ICurve.sol";
import {IPair} from "../../src/interfaces/IPair.sol";
import {ERC7007Launch} from "../../src/ERC7007Launch.sol";
import {ORAERC7007Impl} from "../../src/nft/ORAERC7007Impl.sol";
import {IntegrationBase} from "./IntegrationBase.t.sol";
import {MockAIOracle} from "../mocks/MockAIOracle.t.sol";
import {MockRandOracle} from "../mocks/MockRandOracle.t.sol";
import {Solarray} from "../utils/Solarray.sol";
import {OracleGasEstimator} from "../../src/libraries/OracleGasEstimator.sol";

contract Integration_Sepolia is IntegrationBase {
    MockAIOracle mockAIOracle;

    function setUp() public override {
        vm.createSelectFork("sepolia", 7_079_502);
        super.setUp();
    }

    function _configORA() internal override {
        aiOracle = 0x0A0f4321214BB6C7811dD8a71cF587bdaF03f0A0;
        mockAIOracle = new MockAIOracle();
        randOracle = 0x9202fea708886999D3E642B11271D65A67cBE920;
    }

    function testFuzz_Launch(
        uint24 _random
    ) public {
        uint24 _random = 174;
        _configRand(_random);

        vm.startPrank(admin);
        nftCollectionFactoryProxy.setProviderAllowed(aiOracle, true);
        vm.stopPrank();

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

        vm.deal(user1, amount);
        vm.prank(user1);
        address pair = erc7007LaunchProxy.launch{value: amount}(params);
        address nft = IPair(pair).nft();
        assertEq(IPair(pair).owner(), user1);
        assertEq(IERC721(nft).balanceOf(user1), params.initialBuyNum);
        bytes memory aigcDataBefore = ORAERC7007Impl(nft).aigcDataOf(0);
        assertEq(aigcDataBefore.length, 0);

        uint64 randOracleGasLimit =
            OracleGasEstimator.getRandOracleCallbackGasLimit(params.initialBuyNum, bytes(prompt).length);
        _invokeRandOracle(params.initialBuyNum, nft, randOracleGasLimit);
        _invokeAIOracle(params.initialBuyNum);
        bytes memory aigcDataAFter = ORAERC7007Impl(nft).aigcDataOf(0);
        assertGt(aigcDataAFter.length, 0);
    }

    function _invokeRandOracle(uint256 num, address nft, uint64 gasLimit) internal {
        uint256[] memory tokenIds = new uint256[](num);
        for (uint256 i = 0; i < num; i++) {
            tokenIds[i] = i;
        }
        bytes32 requestId = keccak256(abi.encodePacked(tokenIds));

        // for randOraclerequestId = 1
        uint256 baseSlot = 0xa7c5ba7114a813b50159add3a36832908dc83db71d0b9a24c2ad0f83be958207;
        bytes32 value = bytes32(uint256(uint160(nft)) | (uint256(gasLimit) << 160));
        vm.store(randOracle, bytes32(baseSlot + 4), value);

        bytes memory callbackData = abi.encode(requestId, address(oraOracleDelegateCallerProxy));
        storeBytes(randOracle, bytes32(baseSlot + 5), callbackData);

        (bool success, bytes memory result) =
            randOracle.staticcall(abi.encodeWithSelector(bytes4(keccak256("requests(uint256)")), 1));
        require(success);
        (,,,, address callbackAddr, uint64 _gasLimit,) =
            abi.decode(result, (address, uint256, uint256, bytes, address, uint64, bytes));
        require(callbackAddr == nft);
        require(_gasLimit == gasLimit);

        bytes memory invokeData =
            hex"8f4e027800000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000060000000000000000000000000000000000000000000000000000000000000014000000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002124dbfa306ab916940b2694a37ab7616cf7ee003443d6482e4f614ef0f10aaf524e08c7296a6d933bc51bc4887197b71944874fa24213270b1be9eb9420128147c59ae34b99b82ffde2e1f05cb8710e34971f18750123fd02ee72d185b76d6592a3a65706ce52b612acb8a974e2d04c78eded108dec4022177e297f5331a0b6600000000000000000000000000000000000000000000000000000000000000c000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000000002124dbfa306ab916940b2694a37ab7616cf7ee003443d6482e4f614ef0f10aaf524e08c7296a6d933bc51bc4887197b71944874fa24213270b1be9eb9420128147c59ae34b99b82ffde2e1f05cb8710e34971f18750123fd02ee72d185b76d6592a3a65706ce52b612acb8a974e2d04c78eded108dec4022177e297f5331a0b66";
        vm.prank(0x25290C1B300a49690EeB18701d217d9D7797c8Dc);
        (success,) = randOracle.call(invokeData);
        require(success);
    }

    function _invokeAIOracle(
        uint256 num
    ) internal {
        uint256 requestId = 19_869;
        bytes memory output = mockAIOracle.makeOutput(num);
        vm.prank(0xf5aeB5A4B35be7Af7dBfDb765F99bCF479c917BD);
        MockAIOracle(aiOracle).invokeCallback(requestId, output);
    }

    function storeBytes(address target, bytes32 slot, bytes memory data) internal {
        bytes32 lengthSlot = slot;
        uint256 dataLength = data.length;
        require(dataLength >= 32, "dataLength is too small");
        vm.store(target, lengthSlot, bytes32(dataLength * 2 + 1));

        bytes32 contentSlot = keccak256(abi.encode(slot));
        for (uint256 i; i < (dataLength + 31) / 32; i++) {
            bytes32 word;
            assembly {
                word := mload(add(add(data, 32), mul(i, 32)))
            }
            vm.store(target, bytes32(uint256(contentSlot) + i), word);
        }
    }
}
