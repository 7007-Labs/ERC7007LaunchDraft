// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {NFTCollectionFactory} from "../../src/nft/NFTCollectionFactory.sol";
import {ORAERC7007Impl} from "../../src/nft/ORAERC7007Impl.sol";
import {IAIOracle} from "../../src/interfaces/IAIOracle.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract NFTCollectionFactoryTest is Test {
    NFTCollectionFactory factory;
    ORAERC7007Impl implementation;
    address owner = makeAddr("owner");
    address provider = makeAddr("provider");
    address user = makeAddr("user");
    IAIOracle aiOracle = IAIOracle(makeAddr("aiOracle"));
    uint256 modelId = 50;

    // event GasReport(uint256 promptLength, uint256 gasUsed);

    function setUp() public {
        implementation = new ORAERC7007Impl(aiOracle);

        NFTCollectionFactory factoryImpl = new NFTCollectionFactory();

        bytes memory initData =
            abi.encodeWithSelector(NFTCollectionFactory.initialize.selector, owner, address(implementation));
        ERC1967Proxy proxy = new ERC1967Proxy(address(factoryImpl), initData);
        factory = NFTCollectionFactory(address(proxy));
    }

    function _configProviderAndModel() internal {
        vm.startPrank(owner);
        factory.setProviderAllowed(provider, true);
        factory.setORAModelAllowed(modelId, true);
        vm.stopPrank();
    }

    function test_Initialize() public {
        assertEq(factory.owner(), owner);
        assertEq(factory.nftCollectionImpl(), address(implementation));
    }

    function test_SetProviderAllowed() public {
        vm.startPrank(owner);
        factory.setProviderAllowed(provider, true);
        assertTrue(factory.providerAllowed(provider));

        factory.setProviderAllowed(provider, false);
        assertFalse(factory.providerAllowed(provider));
        vm.stopPrank();
    }

    function test_Revert_SetProviderAllowed_IfNotOwner() public {
        vm.startPrank(user);
        vm.expectRevert();
        factory.setProviderAllowed(provider, true);
        vm.stopPrank();
    }

    function test_SetORAModelAllowed() public {
        vm.startPrank(owner);
        factory.setORAModelAllowed(modelId, true);
        assertTrue(factory.oraModelAllowed(modelId));

        factory.setORAModelAllowed(modelId, false);
        assertFalse(factory.oraModelAllowed(modelId));
        vm.stopPrank();
    }

    function test_Revert_SetORAModelAllowed_IfNotOwner() public {
        vm.startPrank(user);
        vm.expectRevert();
        factory.setORAModelAllowed(1, true);
        vm.stopPrank();
    }

    function test_CreateNFTCollection() public {
        _configProviderAndModel();

        string memory name = "Test NFT";
        string memory symbol = "TEST";
        string memory prompt = "Test prompt";
        bool nsfw = false;
        bytes memory providerParams = abi.encode(modelId);

        vm.startPrank(user);
        address collection = factory.createNFTCollection(name, symbol, prompt, user, nsfw, provider, providerParams);
        vm.stopPrank();

        assertTrue(collection != address(0));
        assertEq(ORAERC7007Impl(collection).owner(), user);
        assertEq(ORAERC7007Impl(collection).name(), name);
        assertEq(ORAERC7007Impl(collection).symbol(), symbol);
        assertEq(address(ORAERC7007Impl(collection).aiOracle()), address(aiOracle));
    }

    function test_CreateNFTCollection_multi() public {
        _configProviderAndModel();
        string memory name = "Test NFT";
        string memory symbol = "TEST";
        string memory prompt = "Test prompt";

        bool nsfw = false;
        bytes memory providerParams = abi.encode(modelId);

        vm.startPrank(user);
        factory.createNFTCollection(name, symbol, prompt, user, nsfw, provider, providerParams);
        vm.stopPrank();

        string memory prompt2 = "Test prompt2";
        factory.createNFTCollection(name, symbol, prompt2, user, nsfw, provider, providerParams);

        address newProvider = makeAddr("newProvider");
        uint256 newModelId = uint256(keccak256("new modelId"));
        vm.startPrank(owner);
        factory.setProviderAllowed(newProvider, true);
        factory.setORAModelAllowed(newModelId, true);
        vm.stopPrank();
        factory.createNFTCollection(name, symbol, prompt, user, nsfw, newProvider, providerParams);

        bytes memory newProviderParams = abi.encode(newModelId);
        factory.createNFTCollection(name, symbol, prompt, user, nsfw, provider, newProviderParams);
    }

    function test_Revert_CreateNFTCollection_DuplicatePromptAndProvider() public {
        _configProviderAndModel();

        string memory name = "Test NFT";
        string memory symbol = "TEST";
        string memory prompt = "Test prompt";

        bool nsfw = false;
        bytes memory providerParams = abi.encode(modelId);

        vm.startPrank(user);
        address collection = factory.createNFTCollection(name, symbol, prompt, user, nsfw, provider, providerParams);
        vm.stopPrank();

        string memory name2 = "name2";
        string memory symbol2 = "T2";
        vm.expectRevert();
        factory.createNFTCollection(name2, symbol2, prompt, user, nsfw, provider, providerParams);
    }

    function test_CreateNFTCollection_ProviderNotAllowed() public {
        _configProviderAndModel();
        address newProvider = makeAddr("newProvider");
        bytes memory providerParams = abi.encode(modelId);
        vm.startPrank(user);
        vm.expectRevert();
        factory.createNFTCollection("Test NFT", "TEST", "Test prompt", user, false, newProvider, providerParams);
        vm.stopPrank();
    }

    function test_CreateNFTCollection_ModelNotAllowed() public {
        _configProviderAndModel();

        uint256 _modelId = 1;
        bytes memory providerParams = abi.encode(_modelId);

        vm.startPrank(user);
        vm.expectRevert();
        factory.createNFTCollection("Test NFT", "TEST", "Test prompt", user, false, provider, providerParams);
        vm.stopPrank();
    }

    function test_Upgrade() public {
        NFTCollectionFactory newImpl = new NFTCollectionFactory();

        vm.startPrank(owner);
        UUPSUpgradeable(factory).upgradeToAndCall(address(newImpl), "");
        vm.stopPrank();
    }

    function test_Upgrade_OnlyOwner() public {
        NFTCollectionFactory newImpl = new NFTCollectionFactory();

        vm.startPrank(user);
        vm.expectRevert();
        UUPSUpgradeable(factory).upgradeToAndCall(address(newImpl), "");
        vm.stopPrank();
    }

    // Test specific prompt lengths to analyze gas patterns
    function test_PromptLengthGasImpact_Fixed() public {
        _configProviderAndModel();
        bytes memory providerParams = abi.encode(modelId);

        // Test with different fixed lengths to see the pattern
        uint256[] memory lengths = new uint256[](5);
        lengths[0] = 10; // Very short prompt
        lengths[1] = 100; // Short prompt
        lengths[2] = 250; // Medium prompt
        lengths[3] = 500; // Long prompt
        lengths[4] = 1000; // Very long prompt

        for (uint256 i = 0; i < lengths.length; i++) {
            string memory prompt = _generatePrompt(lengths[i]);

            uint256 gasBefore = gasleft();
            factory.createNFTCollection("Test NFT", "TEST", prompt, user, false, provider, providerParams);
            uint256 gasUsed = gasBefore - gasleft();

            // emit GasReport(lengths[i], gasUsed);
            console.log("gasReport: %d - %d", lengths[i], gasUsed);
        }
    }

    // Fuzzy test with random prompt lengths
    function testFuzz_PromptLengthGasImpact(
        uint256 promptLength
    ) public {
        // Bound prompt length between 10 and 1000 characters
        promptLength = bound(promptLength, 10, 1000);

        _configProviderAndModel();
        string memory prompt = _generatePrompt(promptLength);
        bytes memory providerParams = abi.encode(modelId);
        factory.createNFTCollection("Test NFT", "TEST", prompt, user, false, provider, providerParams);
    }

    function _generatePrompt(
        uint256 length
    ) internal pure returns (string memory) {
        bytes memory promptBytes = new bytes(length);

        // Fill with repeating pattern of lowercase letters
        for (uint256 i = 0; i < length; i++) {
            promptBytes[i] = bytes1(uint8(97 + (i % 26))); // 97 is 'a' in ASCII
        }

        return string(promptBytes);
    }
}
