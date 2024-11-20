// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {Test, console} from "forge-std/Test.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {NFTCollectionFactory} from "../../src/nft/NFTCollectionFactory.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract MockERC7007 is OwnableUpgradeable {
    string public basePrompt;
    bytes public metadata;
    uint256 public modelId;

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _owner,
        string calldata prompt,
        bytes calldata metadataInitializer,
        uint256 _modelId
    ) external initializer {
        __Ownable_init(_owner);
        basePrompt = prompt;
        metadata = metadataInitializer;
        modelId = _modelId;
    }
}

contract NFTCollectionFactoryTest is Test {
    NFTCollectionFactory factory;
    address nftImpl;
    address owner = makeAddr("owner");
    address user = makeAddr("user");
    address provider = makeAddr("provider");
    uint256 modelId = 50;

    function setUp() public {
        nftImpl = address(new MockERC7007());

        NFTCollectionFactory factoryImpl = new NFTCollectionFactory();

        bytes memory initData =
            abi.encodeWithSelector(NFTCollectionFactory.initialize.selector, owner, address(nftImpl));
        ERC1967Proxy proxy = new ERC1967Proxy(address(factoryImpl), initData);
        factory = NFTCollectionFactory(address(proxy));
    }

    function _configProviderAndModel() internal {
        vm.startPrank(owner);
        factory.setProviderAllowed(provider, true);
        factory.setORAModelAllowed(modelId, true);
        vm.stopPrank();
    }

    function _configAllowlist() internal {
        vm.startPrank(owner);
        factory.setAllowlistAllowed(address(this), true);
        factory.setAllowlistAllowed(user, true);
        vm.stopPrank();
    }

    function test_Initialize() public {
        assertEq(factory.owner(), owner);
        assertEq(factory.nftCollectionImpl(), address(nftImpl));
    }

    function test_SetProviderAllowed() public {
        vm.startPrank(owner);
        factory.setProviderAllowed(provider, true);
        assertTrue(factory.providerAllowed(provider));

        factory.setProviderAllowed(provider, false);
        assertFalse(factory.providerAllowed(provider));
        vm.stopPrank();

        address newProvider = makeAddr("newProvider");
        assertFalse(factory.providerAllowed(newProvider));
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

        uint256 newModelId = 7007;
        assertFalse(factory.oraModelAllowed(newModelId));
    }

    function test_Revert_SetORAModelAllowed_IfNotOwner() public {
        vm.startPrank(user);
        vm.expectRevert();
        factory.setORAModelAllowed(1, true);
        vm.stopPrank();
    }

    function test_CreateNFTCollection() public {
        _configProviderAndModel();
        _configAllowlist();

        string memory prompt = "Test prompt";
        bytes memory providerParams = abi.encode(modelId);
        bytes memory metadataInitializer = bytes("metadata");
        vm.startPrank(user);
        address collection = factory.createNFTCollection(user, prompt, metadataInitializer, provider, providerParams);
        vm.stopPrank();

        assertTrue(collection != address(0));
        assertEq(MockERC7007(collection).owner(), user);
        assertEq(MockERC7007(collection).basePrompt(), prompt);
        assertEq(MockERC7007(collection).metadata(), metadataInitializer);
        assertEq(MockERC7007(collection).modelId(), modelId);
    }

    function test_Revert_CreateNFTCollection_NotAllowed() public {
        _configProviderAndModel();
        _configAllowlist();

        string memory prompt = "Test prompt";
        bytes memory providerParams = abi.encode(modelId);
        bytes memory metadataInitializer = bytes("metadata");
        address newCaller = makeAddr("newCaller");
        vm.prank(newCaller);
        vm.expectRevert();
        factory.createNFTCollection(user, prompt, metadataInitializer, provider, providerParams);
    }

    function test_CreateNFTCollection_multi() public {
        _configProviderAndModel();
        _configAllowlist();

        string memory prompt = "Test prompt";
        bytes memory providerParams = abi.encode(modelId);
        bytes memory metadataInitializer = bytes("metadata");

        vm.startPrank(user);
        factory.createNFTCollection(user, prompt, metadataInitializer, provider, providerParams);
        vm.stopPrank();

        string memory newPrompt = "New test prompt";
        factory.createNFTCollection(user, newPrompt, metadataInitializer, provider, providerParams);

        address newProvider = makeAddr("newProvider");
        uint256 newModelId = uint256(keccak256("new modelId"));
        vm.startPrank(owner);
        factory.setProviderAllowed(newProvider, true);
        factory.setORAModelAllowed(newModelId, true);
        vm.stopPrank();
        factory.createNFTCollection(user, prompt, metadataInitializer, newProvider, providerParams);

        bytes memory newProviderParams = abi.encode(newModelId);
        factory.createNFTCollection(user, prompt, metadataInitializer, provider, newProviderParams);
    }

    function test_Revert_CreateNFTCollection_DuplicatePromptAndProvider() public {
        _configProviderAndModel();
        _configAllowlist();

        string memory prompt = "Test prompt";
        bytes memory providerParams = abi.encode(modelId);
        bytes memory metadataInitializer = bytes("metadata");

        vm.startPrank(user);
        factory.createNFTCollection(user, prompt, metadataInitializer, provider, providerParams);
        vm.stopPrank();

        address newUser = makeAddr("newUser");
        vm.prank(owner);
        factory.setAllowlistAllowed(newUser, true);

        vm.expectRevert();
        factory.createNFTCollection(newUser, prompt, metadataInitializer, provider, providerParams);

        vm.expectRevert();
        factory.createNFTCollection(user, prompt, metadataInitializer, provider, providerParams);
    }

    function test_Revert_CreateNFTCollection_ProviderNotAllowed() public {
        _configAllowlist();
        string memory prompt = "Test prompt";
        bytes memory providerParams = abi.encode(modelId);
        bytes memory metadataInitializer = bytes("metadata");

        vm.prank(user);
        vm.expectRevert();
        factory.createNFTCollection(user, prompt, metadataInitializer, provider, providerParams);
    }

    function test_CreateNFTCollection_ModelNotAllowed() public {
        _configAllowlist();

        string memory prompt = "Test prompt";
        bytes memory providerParams = abi.encode(modelId);
        bytes memory metadataInitializer = bytes("metadata");

        vm.prank(user);
        vm.expectRevert();
        factory.createNFTCollection(user, prompt, metadataInitializer, provider, providerParams);
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
}
