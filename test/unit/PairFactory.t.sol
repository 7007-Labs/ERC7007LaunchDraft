// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test} from "forge-std/Test.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

import {PairFactory} from "../../src/PairFactory.sol";
import {PairERC7007ETH} from "../../src/PairERC7007ETH.sol";
import {IPair} from "../../src/interfaces/IPair.sol";
import {ICurve} from "../../src/interfaces/ICurve.sol";
import {PairType} from "../../src/enums/PairType.sol";

contract MockPairERC7007ETH is Initializable, OwnableUpgradeable {
    address public nft;
    address public propertyChecker;
    uint256 public nftTotalSupply;
    IPair.SalesConfig public salesConfig;

    function initialize(
        address _owner,
        address _nft,
        address _propertyChecker,
        uint256 _nftTotalSupply,
        IPair.SalesConfig calldata _salesConfig
    ) external initializer {
        __Ownable_init(_owner);
        nft = _nft;
        propertyChecker = _propertyChecker;
        nftTotalSupply = _nftTotalSupply;
        salesConfig = _salesConfig;
    }
}

contract PairFactoryTest is Test {
    PairFactory public factory;
    address public owner = makeAddr("owner");
    address public user = makeAddr("user");
    address public nft = makeAddr("nft");
    address public propertyChecker = makeAddr("propertyChecker");
    address public bondingCurve = makeAddr("bondingCurve");

    address public erc7007ETHImpl;
    address public erc7007ETHBeacon;

    function setUp() public {
        erc7007ETHImpl = address(new MockPairERC7007ETH());
        erc7007ETHBeacon = address(new UpgradeableBeacon(erc7007ETHImpl, owner));
        PairFactory impl = new PairFactory();
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        factory = PairFactory(address(proxy));
        factory.initialize(owner, erc7007ETHBeacon);

        vm.startPrank(owner);
        factory.setBondingCurveAllowed(bondingCurve, true);
        factory.setAllowlistAllowed(user, true);
        vm.stopPrank();
    }

    function test_Initialize() public view {
        assertEq(factory.owner(), owner);
        assertEq(factory.erc7007ETHBeacon(), erc7007ETHBeacon);
    }

    function _buildPairParams(
        address _bondingCurve
    ) internal pure returns (bytes memory) {
        IPair.SalesConfig memory salesConfig = IPair.SalesConfig({
            maxPresalePurchasePerAddress: 1,
            presaleMaxNum: 100,
            presaleStart: 0,
            presaleEnd: 0,
            publicSaleStart: 0,
            presalePrice: 0.0001 ether,
            bondingCurve: ICurve(_bondingCurve),
            presaleMerkleRoot: bytes32(0)
        });
        uint256 nftTotalSupply = 7007;
        return abi.encode(nftTotalSupply, salesConfig);
    }

    function test_CreatePairERC7007ETH() public {
        bytes memory params = _buildPairParams(bondingCurve);

        vm.prank(user);
        address pair = factory.createPairERC7007ETH(user, nft, PairType.LAUNCH, propertyChecker, params);

        assertEq(IPair(pair).owner(), user);
    }

    function test_Revert_CreatePairERC7007ETH_IfNotAllowed() public {
        bytes memory params = _buildPairParams(bondingCurve);
        address newUser = makeAddr("newUser");

        vm.prank(newUser);
        vm.expectRevert();
        factory.createPairERC7007ETH(user, nft, PairType.LAUNCH, propertyChecker, params);
    }

    function test_Revert_CreatePairERC7007ETH_WhenUsingDisallowedBondingCurve() public {
        address newCurve = makeAddr("newBondingCurve");
        bytes memory params = _buildPairParams(newCurve);

        vm.prank(user);
        vm.expectRevert();
        factory.createPairERC7007ETH(user, nft, PairType.LAUNCH, propertyChecker, params);
    }

    function test_SetRouterAllowed() public {
        address router = makeAddr("router");

        vm.startPrank(owner);
        factory.setRouterAllowed(router, true);

        assertTrue(factory.isRouterAllowed(router));

        factory.setRouterAllowed(router, false);

        assertFalse(factory.isRouterAllowed(router));
        vm.stopPrank();
    }

    function test_SetBondingCurveAllowed() public {
        address curve = makeAddr("curve");

        vm.startPrank(owner);
        factory.setBondingCurveAllowed(curve, true);

        assertTrue(factory.bondingCurveAllowed(curve));

        factory.setBondingCurveAllowed(curve, false);

        assertFalse(factory.bondingCurveAllowed(curve));
        vm.stopPrank();
    }

    function test_SetAllowlistAllowed() public {
        address addr = makeAddr("addr");

        vm.startPrank(owner);
        factory.setAllowlistAllowed(addr, true);

        assertTrue(factory.allowlist(addr));

        factory.setAllowlistAllowed(addr, false);

        assertFalse(factory.allowlist(addr));
        vm.stopPrank();
    }

    function test_Revert_WhenNonOwnerCallsAdminFunctions() public {
        vm.startPrank(user);

        vm.expectRevert();
        factory.setRouterAllowed(makeAddr("router"), true);

        vm.expectRevert();
        factory.setBondingCurveAllowed(makeAddr("curve"), true);

        vm.expectRevert();
        factory.setAllowlistAllowed(makeAddr("addr"), true);

        vm.stopPrank();
    }

    function test_UpgradeAuthorization() public {
        address newImpl = address(new PairFactory());

        vm.prank(user);
        vm.expectRevert();
        factory.upgradeToAndCall(newImpl, "");

        vm.prank(owner);
        factory.upgradeToAndCall(newImpl, "");
    }
}
