// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ORAOracleDelegateCaller} from "../../src/ORAOracleDelegateCaller.sol";
import {IAIOracle} from "../../src/interfaces/IAIOracle.sol";
import {IRandOracle} from "../../src/interfaces/IRandOracle.sol";
import {MockAIOracle} from "../mocks/MockAIOracle.t.sol";
import {MockRandOracle} from "../mocks/MockRandOracle.t.sol";

contract ORAOracleDelegateCallerTest is Test {
    ORAOracleDelegateCaller public delegateCaller;
    MockAIOracle public mockAIOracle;
    MockRandOracle public mockRandOracle;

    address public owner = makeAddr("owner");
    address public operator = makeAddr("operator");
    address public nft = makeAddr("nft");
    address public user = makeAddr("user");

    function setUp() public {
        mockAIOracle = new MockAIOracle();
        mockRandOracle = new MockRandOracle();

        ORAOracleDelegateCaller impl =
            new ORAOracleDelegateCaller(IAIOracle(address(mockAIOracle)), IRandOracle(address(mockRandOracle)));
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        delegateCaller = ORAOracleDelegateCaller(payable(proxy));

        delegateCaller.initialize(owner);

        vm.prank(owner);
        delegateCaller.setOperator(operator);

        vm.prank(operator);
        delegateCaller.addToAllowlist(nft);
    }

    function test_Initialize() public view {
        assertEq(delegateCaller.owner(), owner);
        assertEq(delegateCaller.operator(), operator);
    }

    function test_AddToAllowlist() public {
        address newUser = makeAddr("newUser");

        vm.prank(operator);
        delegateCaller.addToAllowlist(newUser);

        assertTrue(delegateCaller.allowlist(newUser));
    }

    function test_Revert_AddToAllowlist_Unauthorized() public {
        address newUser = makeAddr("newUser");

        vm.expectRevert();
        delegateCaller.addToAllowlist(newUser);
    }

    function test_SetOperator() public {
        address newOperator = makeAddr("newOperator");

        vm.prank(owner);
        delegateCaller.setOperator(newOperator);

        assertEq(delegateCaller.operator(), newOperator);
    }

    function test_Revert_SetOperator_Unauthorized() public {
        address newOperator = makeAddr("newOperator");

        vm.expectRevert();
        delegateCaller.setOperator(newOperator);
    }

    function test_RequestRandOracle() public {
        vm.deal(nft, 1 ether);
        vm.prank(nft);
        uint256 requestId = _requestRandOracle();
        assertGt(requestId, 0);
    }

    function _requestRandOracle() internal returns (uint256) {
        return delegateCaller.requestRandOracle{value: 1 ether}(0, bytes(""), address(this), 100, bytes(""));
    }

    function test_Revert_RequestRandOracle_Unauthorized() public {
        vm.expectRevert(ORAOracleDelegateCaller.UnauthorizedCaller.selector);
        _requestRandOracle();
    }

    function test_RequestAIOracleBatchInference() public {
        vm.deal(nft, 1 ether);
        vm.prank(nft);
        uint256 requestId = _requestAIOracleBatchInference();

        assertEq(requestId, 1);
    }

    function _requestAIOracleBatchInference() internal returns (uint256) {
        return delegateCaller.requestAIOracleBatchInference{value: 1 ether}(
            1, 50, bytes(""), address(this), 100, bytes(""), IAIOracle.DA.Calldata, IAIOracle.DA.Calldata
        );
    }

    function test_Revert_RequestAIOracleBatchInference_Unauthorized() public {
        vm.expectRevert(ORAOracleDelegateCaller.UnauthorizedCaller.selector);
        _requestAIOracleBatchInference();
    }

    function test_WithdrawETH() public {
        uint256 amount = 1 ether;
        address recipient = makeAddr("recipient");

        vm.deal(address(delegateCaller), amount);

        vm.prank(owner);
        delegateCaller.withdrawETH(recipient, amount);

        assertEq(address(recipient).balance, amount);
        assertEq(address(delegateCaller).balance, 0);
    }

    function test_Revert_WithdrawETH_Unauthorized() public {
        uint256 amount = 1 ether;
        address recipient = address(5);

        vm.deal(address(delegateCaller), amount);

        vm.prank(user);
        vm.expectRevert();
        delegateCaller.withdrawETH(recipient, amount);
    }

    function test_ReceiveETH() public {
        uint256 amount = 1 ether;

        vm.deal(user, amount);
        vm.prank(user);
        (bool success,) = address(delegateCaller).call{value: amount}("");

        assertTrue(success);
        assertEq(address(delegateCaller).balance, amount);
    }
}
