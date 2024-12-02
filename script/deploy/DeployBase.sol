// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import "forge-std/Script.sol";

import "./ExistingDeploymentParser.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {IAIOracle} from "../../src/interfaces/IAIOracle.sol";
import {IRandOracle} from "../../src/interfaces/IRandOracle.sol";

abstract contract DeployBase is ExistingDeploymentParser {
    address protocolFeeRecipient;
    address admin;

    function deploy() public {
        _configORA();
        _deployBondCurves();
        _deployFromScratch();
        _configPermission();
        _transferOwnership();
    }

    function verifyDeploy() public {
        _verifyImpl();
    }

    function _verifyImpl() internal virtual {
        // Verify RoyaltyExecutor
        address royaltyExecutorImplAddr = _getImplementation(address(royaltyExecutorProxy));
        require(royaltyExecutorImplAddr == address(royaltyExecutorImpl), "RoyaltyExecutor implementation mismatch");

        // Verify NFTCollectionFactory
        address nftCollectionFactoryImplAddr = _getImplementation(address(nftCollectionFactoryProxy));
        require(
            nftCollectionFactoryImplAddr == address(nftCollectionFactoryImpl),
            "NFTCollectionFactory implementation mismatch"
        );

        // Verify ORAOracleDelegateCaller
        address oraOracleDelegateCallerImplAddr = _getImplementation(address(oraOracleDelegateCallerProxy));
        require(
            oraOracleDelegateCallerImplAddr == address(oraOracleDelegateCallerImpl),
            "ORAOracleDelegateCaller implementation mismatch"
        );

        // Verify PairFactory
        address pairFactoryImplAddr = _getImplementation(address(pairFactoryProxy));
        require(pairFactoryImplAddr == address(pairFactoryImpl), "PairFactory implementation mismatch");

        // Verify ERC7007Launch
        address erc7007LaunchImplAddr = _getImplementation(address(erc7007LaunchProxy));
        require(erc7007LaunchImplAddr == address(erc7007LaunchImpl), "ERC7007Launch implementation mismatch");
    }

    function _getImplementation(
        address proxy
    ) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967Utils.IMPLEMENTATION_SLOT))));
    }

    function _deployFromScratch() internal virtual {
        royaltyExecutorImpl = new RoyaltyExecutor();
        royaltyExecutorProxy = RoyaltyExecutor(
            address(
                new ERC1967Proxy(
                    address(royaltyExecutorImpl), abi.encodeWithSelector(RoyaltyExecutor.initialize.selector, admin)
                )
            )
        );

        oraERC7007Impl = new ORAERC7007Impl(IAIOracle(aiOracle), IRandOracle(randOracle));

        nftCollectionFactoryImpl = new NFTCollectionFactory();
        nftCollectionFactoryProxy = NFTCollectionFactory(
            address(
                new ERC1967Proxy(
                    address(nftCollectionFactoryImpl),
                    abi.encodeWithSelector(NFTCollectionFactory.initialize.selector, admin, address(oraERC7007Impl))
                )
            )
        );

        oraOracleDelegateCallerImpl = new ORAOracleDelegateCaller(IAIOracle(aiOracle), IRandOracle(randOracle));
        oraOracleDelegateCallerProxy = ORAOracleDelegateCaller(
            payable(
                new ERC1967Proxy(
                    address(oraOracleDelegateCallerImpl),
                    abi.encodeWithSelector(ORAOracleDelegateCaller.initialize.selector, admin)
                )
            )
        );

        pairFactoryImpl = new PairFactory(oraOracleDelegateCallerProxy);
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

        pairERC7007ETHImpl = new PairERC7007ETH(
            address(pairFactoryProxy),
            address(royaltyExecutorProxy),
            address(feeManagerProxy),
            address(oraOracleDelegateCallerProxy)
        );
        pairERC7007ETHBeacon = new UpgradeableBeacon(address(pairERC7007ETHImpl), admin);
        pairFactoryProxy.initialize(admin, address(pairERC7007ETHBeacon));

        erc7007LaunchImpl = new ERC7007Launch(address(nftCollectionFactoryProxy), address(pairFactoryProxy));
        erc7007LaunchProxy = ERC7007Launch(
            payable(
                new ERC1967Proxy(
                    address(erc7007LaunchImpl), abi.encodeWithSelector(ERC7007Launch.initialize.selector, admin)
                )
            )
        );
    }

    function _configORA() internal virtual {
        aiOracle = 0x0A0f4321214BB6C7811dD8a71cF587bdaF03f0A0;
        randOracle = 0x9202fea708886999D3E642B11271D65A67cBE920;
    }

    function _deployBondCurves() internal virtual {
        ExponentialCurve curve = new ExponentialCurve();
        bondingCurves.push(DeployedBondingCurve({name: type(ExponentialCurve).name, addr: address(curve)}));
    }

    function _configPermission() internal virtual {
        pairFactoryProxy.setRouterAllowed(address(erc7007LaunchProxy), true);
        pairFactoryProxy.setAllowlistAllowed(address(erc7007LaunchProxy), true);
        for (uint256 i = 0; i < bondingCurves.length; i++) {
            pairFactoryProxy.setBondingCurveAllowed(bondingCurves[i].addr, true);
        }

        nftCollectionFactoryProxy.setAllowlistAllowed(address(erc7007LaunchProxy), true);
        nftCollectionFactoryProxy.setProviderAllowed(aiOracle, true);
        nftCollectionFactoryProxy.setORAModelAllowed(50, true);

        oraOracleDelegateCallerProxy.setOperator(address(pairFactoryProxy));
    }

    function _transferOwnership() internal virtual {}
}
