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

contract Integration_Base is IntegrationBase {
    MockAIOracle mockAIOracle;

    function setUp() public override {
        vm.createSelectFork("base", 23_089_651);
        super.setUp();
    }

    function _configORA() internal override {
        aiOracle = 0x0A0f4321214BB6C7811dD8a71cF587bdaF03f0A0;
        mockAIOracle = new MockAIOracle();
        randOracle = address(new MockRandOracle());
    }

    function testFuzz_Launch(
        uint24 _random
    ) public {
        // uint24 _random = 12;
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

        vm.deal(user1, 1 ether);
        vm.prank(user1);
        address pair = erc7007LaunchProxy.launch{value: amount}(params);
        address nft = IPair(pair).nft();
        assertEq(IPair(pair).owner(), user1);
        assertEq(IERC721(nft).balanceOf(user1), params.initialBuyNum);
        bytes memory aigcDataBefore = ORAERC7007Impl(nft).aigcDataOf(0);
        assertEq(aigcDataBefore.length, 0);
        _invokeRandOracle();
        _invokeAIOracle(params.initialBuyNum);
        bytes memory aigcDataAFter = ORAERC7007Impl(nft).aigcDataOf(0);
        assertGt(aigcDataAFter.length, 0);
    }

    function _invokeRandOracle() internal {
        uint256 reuestId = MockRandOracle(randOracle).latestRequestId();
        uint256 seed = _randUint(1, type(uint128).max);
        MockRandOracle(randOracle).invoke(reuestId, abi.encodePacked(seed), "");
    }

    function _invokeAIOracle(
        uint256 num
    ) internal {
        uint256 requestId = 2010;
        bytes memory output = mockAIOracle.makeOutput(num);
        vm.prank(0x4Ca146039C567a8CbfDe83c23a515B587d9Be469);
        MockAIOracle(aiOracle).invokeCallback(requestId, output);
    }
}
