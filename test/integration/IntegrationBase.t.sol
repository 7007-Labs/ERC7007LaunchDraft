// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "script/deploy/ExistingDeploymentParser.sol";
import {MockAIOracle} from "../mocks/MockAIOracle.t.sol";
import {MockRandOracle} from "../mocks/MockRandOracle.t.sol";
import {IAIOracle} from "../../src/interfaces/IAIOracle.sol";
import {IRandOracle} from "../../src/interfaces/IRandOracle.sol";

abstract contract IntegrationBase is ExistingDeploymentParser {
    address public aiOracle;
    address public randOracle;
    address public admin;
    address public protocolFeeRecipient;

    bytes32 random;

    function setUp() public virtual {
        _setUpLocal();
    }

    function _setUpLocal() public virtual {
        aiOracle = address(new MockAIOracle());
        randOracle = address(new MockRandOracle());
        admin = makeAddr("admin");
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");
        _deployContracts();
        _configContracts();
    }

    function _deployContracts() internal virtual {
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

        ExponentialCurve curve = new ExponentialCurve();
        bondingCurves.push(DeployedBondingCurve({name: type(ExponentialCurve).name, addr: address(curve)}));
    }

    function _configContracts() internal {
        vm.startPrank(admin);

        for (uint256 i = 0; i < bondingCurves.length; i++) {
            pairFactoryProxy.setBondingCurveAllowed(bondingCurves[i].addr, true);
        }
        pairFactoryProxy.setAllowlistAllowed(address(erc7007LaunchProxy), true);
        pairFactoryProxy.setRouterAllowed(address(erc7007LaunchProxy), true);

        nftCollectionFactoryProxy.setAllowlistAllowed(address(erc7007LaunchProxy), true);
        nftCollectionFactoryProxy.setProviderAllowed(aiOracle, true);
        nftCollectionFactoryProxy.setORAModelAllowed(50, true);

        oraOracleDelegateCallerProxy.setOperator(address(pairFactoryProxy));
        vm.stopPrank();
    }

    function _configRand(
        uint24 _randomSeed
    ) internal {
        random = keccak256(abi.encodePacked(_randomSeed));
    }
    /// @dev Uses `random` to return a random uint, with a range given by `min` and `max` (inclusive)
    /// @return `min` <= result <= `max`

    function _randUint(uint256 min, uint256 max) internal returns (uint256) {
        uint256 range = max - min + 1;

        // calculate the number of bits needed for the range
        uint256 bitsNeeded = 0;
        uint256 tempRange = range;
        while (tempRange > 0) {
            bitsNeeded++;
            tempRange >>= 1;
        }

        // create a mask for the required number of bits
        // and extract the value from the hash
        uint256 mask = (1 << bitsNeeded) - 1;
        uint256 value = uint256(random) & mask;

        // in case value is out of range, wrap around or retry
        while (value >= range) {
            value = (value - range) & mask;
        }

        // Hash `random` with itself so the next value we generate is different
        random = keccak256(abi.encodePacked(random));
        return min + value;
    }

    function _randBool() internal returns (bool) {
        return _randUint({min: 0, max: 1}) == 0;
    }
}
