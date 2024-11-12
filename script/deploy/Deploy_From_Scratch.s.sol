// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import "forge-std/Script.sol";

import "./ExistingDeploymentParser.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAIOracle} from "../../src/interfaces/IAIOracle.sol";

contract Deploy is ExistingDeploymentParser {
    address aiOracle = 0x0A0f4321214BB6C7811dD8a71cF587bdaF03f0A0;
    address token7007 = vm.addr(7007);
    address protocolFeeRecipient = vm.addr(7007);
    address admin = vm.addr(1);

    function run() public {
        vm.startBroadcast();
        _deployFromScrath();
        _deployBondCurves();
        _configORA();
        _configBondingCurves();
        vm.stopBroadcast();

        outputContractAddresses(getOutputPath());
    }

    function _deployFromScrath() internal {
        royaltyManagerImpl = new RoyaltyManager();
        royaltyManagerProxy = RoyaltyManager(
            address(
                new ERC1967Proxy(
                    address(royaltyManagerImpl), abi.encodeWithSelector(RoyaltyManager.initialize.selector, admin)
                )
            )
        );

        oraERC7007Impl = new ORAERC7007Impl(IAIOracle(aiOracle));

        nftCollectionFactoryImpl = new NFTCollectionFactory();
        nftCollectionFactoryProxy = NFTCollectionFactory(
            address(
                new ERC1967Proxy(
                    address(nftCollectionFactoryImpl),
                    abi.encodeWithSelector(NFTCollectionFactory.initialize.selector, admin, address(oraERC7007Impl))
                )
            )
        );

        pairFactoryImpl = new PairFactory();
        pairFactoryProxy = PairFactory(address(new ERC1967Proxy(address(pairFactoryImpl), "")));

        feeManagerImpl = new FeeManager();
        feeManagerProxy = FeeManager(
            address(
                new ERC1967Proxy(
                    address(feeManagerImpl),
                    abi.encodeWithSelector(FeeManager.initialize.selector, admin, protocolFeeRecipient)
                )
            )
        );

        transferManager = new TransferManager(address(pairFactoryProxy));

        pairERC7007ETHImpl = new PairERC7007ETH(
            address(pairFactoryProxy), address(royaltyManagerProxy), address(feeManagerProxy), address(transferManager)
        );

        pairFactoryProxy.initialize(admin, address(pairERC7007ETHImpl));

        erc7007LaunchImpl = new ERC7007Launch(address(nftCollectionFactoryProxy), address(pairFactoryProxy), token7007);
        erc7007LaunchProxy = ERC7007Launch(
            address(
                new ERC1967Proxy(
                    address(erc7007LaunchImpl), abi.encodeWithSelector(ERC7007Launch.initialize.selector, admin)
                )
            )
        );
    }

    function _deployBondCurves() internal {
        SimpleCurve curve = new SimpleCurve();
        bondingCurves.push(DeployedBondingCurve({name: type(SimpleCurve).name, addr: address(curve)}));
    }

    function _configORA() internal {
        nftCollectionFactoryProxy.setProviderAllowed(aiOracle, true);
        nftCollectionFactoryProxy.setORAModelAllowed(50, true);
    }

    function _configBondingCurves() internal {
        for (uint256 i = 0; i < bondingCurves.length; i++) {
            pairFactoryProxy.setBondingCurveAllowed(bondingCurves[i].addr, true);
        }
    }

    function _configPermission() internal {
        pairFactoryProxy.setAllowlistAllowed(address(erc7007LaunchProxy), true);
        nftCollectionFactoryProxy.setAllowlistAllowed(address(erc7007LaunchProxy), true);
    }

    function _transferOwnership() internal {}
}
