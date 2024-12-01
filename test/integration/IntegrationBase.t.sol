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

    string[] public prompts = [
        // 18 bytes
        "cute puppy, fluffy",
        // 113 bytes
        "adorable golden retriever puppy playing in grass, sunny day, soft fur, big eyes, playful expression, high quality",
        // 218 bytes
        "a photorealistic portrait of a happy Corgi puppy sitting in a flower garden, morning sunlight, detailed fur texture, sparkling eyes, pink tongue, natural background, professional photography, 8k resolution, high detail",
        // 336 bytes
        "an ultra-detailed photograph of a charming Husky puppy in a snowy landscape, crystal clear blue eyes, perfectly groomed fluffy white and grey fur, wearing a tiny red scarf, snowflakes falling around, golden hour lighting, sharp focus on facial features, professional camera settings, depth of field effect, award-winning pet photography"
    ];

    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");
    address user3 = makeAddr("user3");
    address user4 = makeAddr("user4");
    bytes32 usersMerkleRoot = 0x585f9f8d790909047a9ac2fccd78a4de668596df1d7cf579bd6a9fda19211036;
    bytes32[] user1Proof = [
        bytes32(0xc471bda26e2e9f486b58f8f86bf6b700bb9d0db6dafabec4ee3f352a216fc396),
        bytes32(0x3457fcb5d46c166f9e5742d81aef337030c0bb10f0fbc23bb39da8c6b9e08b4c)
    ];
    bytes32[] user2Proof = [
        bytes32(0x83a81a15f71c60ce0f7ebed1c3ef158329975b28013c5fa91a666413b145287b),
        bytes32(0xcbc3414f08bcfe1a4a5dea214e4c4cc09ea137e41c2c99c7f42c3bf752e335d9)
    ];
    bytes32[] user3Proof = [
        bytes32(0x4e2ef3f4d279d23ce0933035d8c8fb3ce41acb03aa29a326c527a6c76b912f6e),
        bytes32(0xcbc3414f08bcfe1a4a5dea214e4c4cc09ea137e41c2c99c7f42c3bf752e335d9)
    ];
    bytes32[] user4Proof = [
        bytes32(0x9abe6538df951915d55c9917d0f7e1aa3bb7be7dcdb0adec0025066572b270b2),
        bytes32(0x3457fcb5d46c166f9e5742d81aef337030c0bb10f0fbc23bb39da8c6b9e08b4c)
    ];

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
