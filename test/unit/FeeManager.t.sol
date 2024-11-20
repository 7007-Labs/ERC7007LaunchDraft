// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {FeeManager} from "../../src/FeeManager.sol";
import {IFeeManager} from "../../src/interfaces/IFeeManager.sol";
import {IPair} from "../../src/interfaces/IPair.sol";

contract FeeManagerTest is Test {
    FeeManager public feeManager;
    address public owner = makeAddr("owner");
    address public protocolFeeRecipient = makeAddr("protocolFeeRecipient");
    address public pair = makeAddr("pair");

    function setUp() public {
        owner = makeAddr("owner");

        FeeManager feeManagerImpl = new FeeManager();
        ERC1967Proxy proxy = new ERC1967Proxy(address(feeManagerImpl), "");
        feeManager = FeeManager(address(proxy));
        feeManager.initialize(owner, protocolFeeRecipient);
    }

    function test_Initialize() public {
        assertEq(feeManager.owner(), owner);
        assertEq(feeManager.protocolFeeRecipient(), protocolFeeRecipient);
    }

    function test_RegisterPair() public {
        uint16 pairFeeBps = 100;
        uint16 protocolFeeBps = 50;
        address pairFeeRecipient = makeAddr("pairFeeRecipient");

        vm.prank(pair);
        feeManager.registerPair(pairFeeRecipient, pairFeeBps, protocolFeeBps);

        IFeeManager.PairFeeConfig memory config = feeManager.getConfig(pair);
        assertEq(config.feeRecipient, pairFeeRecipient);
        assertEq(config.pairFeeBps, pairFeeBps);
        assertEq(config.protocolFeeBps, protocolFeeBps);
    }

    function test_Revert_RegisterPair_AlreadyRegistered() public {
        uint16 pairFeeBps = 100;
        uint16 protocolFeeBps = 50;
        address pairFeeRecipient = makeAddr("pairFeeRecipient");

        vm.prank(pair);
        feeManager.registerPair(pairFeeRecipient, pairFeeBps, protocolFeeBps);

        vm.prank(pair);
        vm.expectRevert();
        feeManager.registerPair(pairFeeRecipient, pairFeeBps, protocolFeeBps);
    }

    function test_Revert_RegisterPair_IfZeroAddress() public {
        vm.prank(pair);
        vm.expectRevert();
        feeManager.registerPair(address(0), 100, 50);
    }

    function test_Revert_RegisterPair_IfExceedMaximum() public {
        vm.prank(pair);
        vm.expectRevert();
        feeManager.registerPair(makeAddr("recipient"), 4000, 2000);
    }

    function test_CalculateFees() public {
        uint16 pairFeeBps = 300; // 3%
        uint16 protocolFeeBps = 100; // 1%
        address pairFeeRecipient = makeAddr("pairFeeRecipient");
        uint256 amount = 10_000;

        vm.prank(pair);
        feeManager.registerPair(pairFeeRecipient, pairFeeBps, protocolFeeBps);

        (address payable[] memory recipients, uint256[] memory amounts, uint256 totalAmount) =
            feeManager.calculateFees(pair, amount);

        assertEq(recipients[0], pairFeeRecipient);
        assertEq(recipients[1], protocolFeeRecipient);
        assertEq(amounts[0], 300); // 3% of 10000
        assertEq(amounts[1], 100); // 1% of 10000
        assertEq(totalAmount, 400); // Total fees
    }

    function test_Revert_CalculateFees_IfNotRegistered() public {
        vm.expectRevert();
        feeManager.calculateFees(pair, 1000);
    }

    function test_UpdatePairRecipient() public {
        address pairFeeRecipient = makeAddr("pairFeeRecipient");
        address newRecipient = makeAddr("newRecipient");

        vm.prank(pair);
        feeManager.registerPair(pairFeeRecipient, 100, 50);

        address pairOwner = makeAddr("pairOwner");
        vm.mockCall(pair, abi.encodeWithSignature("owner()"), abi.encode(pairOwner));

        vm.prank(pairOwner);
        feeManager.updatePairRecipient(pair, newRecipient);

        IFeeManager.PairFeeConfig memory config = feeManager.getConfig(pair);
        assertEq(config.feeRecipient, newRecipient);
    }

    function test_Revert_UpdatePairRecipient_IfNotPairOwner() public {
        address pairFeeRecipient = makeAddr("pairFeeRecipient");
        address newRecipient = makeAddr("newRecipient");

        vm.prank(pair);
        feeManager.registerPair(pairFeeRecipient, 100, 50);

        address pairOwner = makeAddr("pairOwner");
        vm.mockCall(pair, abi.encodeWithSignature("owner()"), abi.encode(pairOwner));

        vm.expectRevert();
        feeManager.updatePairRecipient(pair, newRecipient);
    }

    function test_UpdateProtocolRecipient() public {
        address newRecipient = makeAddr("newRecipient");

        vm.prank(owner);
        feeManager.updateProtocolRecipient(newRecipient);

        assertEq(feeManager.protocolFeeRecipient(), newRecipient);
    }

    function test_Revert_UpdateProtocolRecipient_IfNotOwner() public {
        vm.expectRevert();
        feeManager.updateProtocolRecipient(makeAddr("newRecipient"));
    }

    function test_UpdatePairFees() public {
        address pairFeeRecipient = makeAddr("pairFeeRecipient");

        vm.prank(pair);
        feeManager.registerPair(pairFeeRecipient, 100, 50);

        uint16 newPairFeeBps = 200;
        uint16 newProtocolFeeBps = 100;
        vm.prank(owner);
        feeManager.updatePairFees(pair, newPairFeeBps, newProtocolFeeBps);

        IFeeManager.PairFeeConfig memory config = feeManager.getConfig(pair);
        assertEq(config.pairFeeBps, newPairFeeBps);
        assertEq(config.protocolFeeBps, newProtocolFeeBps);
    }

    function test_Revert_UpdatePairFees_IfNotOwner() public {
        vm.expectRevert();
        feeManager.updatePairFees(pair, 200, 100);
    }

    function test_Revert_UpdatePairFees_ExceedMaximum() public {
        address pairFeeRecipient = makeAddr("pairFeeRecipient");

        vm.prank(pair);
        feeManager.registerPair(pairFeeRecipient, 100, 50);

        vm.prank(owner);
        vm.expectRevert();
        feeManager.updatePairFees(pair, 4000, 2000);
    }

    function test_Revert_UpdatePairFees_IfPairNotRegistered() public {
        address unRegisteredPair = makeAddr("unRegisteredPair");

        vm.prank(owner);
        vm.expectRevert();
        feeManager.updatePairFees(unRegisteredPair, 10, 10);
    }
}
