// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, Vm, console2} from "forge-std/Test.sol";
import {CompliantRouter} from "../../src/CompliantRouter.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {MockLinkToken} from "./mocks/MockLinkToken.sol";
import {MockEverestConsumer} from "./mocks/MockEverestConsumer.sol";
import {MockAutomationRegistry} from "./mocks/MockAutomationRegistry.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {CompliantProxy} from "../src/proxy/CompliantProxy.sol";
import {InitialImplementation} from "../src/proxy/InitialImplementation.sol";
import {IAutomationRegistrar, RegistrationParams, LogTriggerConfig} from "../src/interfaces/IAutomationRegistrar.sol";
import {IAutomationRegistryMaster} from
    "@chainlink/contracts/src/v0.8/automation/interfaces/v2_2/IAutomationRegistryMaster.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy,
    ProxyAdmin
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {LogicWrapper} from "./wrappers/LogicWrapper.sol";

contract BaseTest is Test {
    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256 internal constant MAINNET_STARTING_BLOCK = 21278732;
    uint256 internal constant USER_LINK_BALANCE = 100 * 1e18;

    CompliantProxy internal compliantProxy;
    CompliantRouter internal compliantRouter;
    MockEverestConsumer internal everest;
    address internal link;
    address internal linkUsdFeed;
    address internal registry;
    address internal registrar;
    address internal forwarder;
    uint256 internal upkeepId;

    address internal deployer = vm.envAddress("DEPLOYER_ADDRESS");
    address internal user = makeAddr("user");
    address internal proxyDeployer = makeAddr("proxyDeployer");
    address internal owner;
    address internal proxyAdmin;
    LogicWrapper internal logic;

    uint256 internal ethMainnetFork;

    uint64 internal defaultGasLimit;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() public virtual {
        /// @dev fork mainnet and initialize contracts
        ethMainnetFork = vm.createSelectFork(vm.envString("MAINNET_RPC_URL"), MAINNET_STARTING_BLOCK);
        HelperConfig config = new HelperConfig();
        (, link, linkUsdFeed, registry, registrar,) = config.activeNetworkConfig();
        everest = new MockEverestConsumer(link);

        /// @dev deploy InitialImplementation
        InitialImplementation initialImplementation = new InitialImplementation();

        /// @dev record logs to get proxyAdmin contract address
        vm.recordLogs();

        /// @dev deploy CompliantProxy
        compliantProxy = new CompliantProxy(address(initialImplementation), proxyDeployer);

        /// @dev get proxyAdmin contract address from logs
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventSignature = keccak256("AdminChanged(address,address)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSignature) {
                (, proxyAdmin) = abi.decode(logs[i].data, (address, address));
            }
        }

        /// @dev register automation
        upkeepId = _registerAutomation(address(compliantProxy), address(everest));
        forwarder = IAutomationRegistryMaster(registry).getForwarder(upkeepId);

        /// @dev deploy CompliantRouter
        vm.prank(deployer);
        compliantRouter =
            new CompliantRouter(address(everest), link, linkUsdFeed, forwarder, upkeepId, address(compliantProxy));

        /// @dev upgradeToAndCall - set CompliantRouter to new implementation and initialize deployer to owner
        bytes memory initializeData = abi.encodeWithSignature("initialize(address)", deployer);
        vm.prank(proxyDeployer);
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(address(compliantProxy)), address(compliantRouter), initializeData
        );

        /// @dev set CompliantProxyAdmin to address(0) - making its last upgrade final and immutable
        vm.prank(proxyDeployer);
        ProxyAdmin(proxyAdmin).renounceOwnership();
        assertEq(ProxyAdmin(proxyAdmin).owner(), address(0));

        /// @dev assign owner
        (, bytes memory ownerData) = address(compliantProxy).call(abi.encodeWithSignature("owner()"));
        owner = abi.decode(ownerData, (address));

        /// @dev deal LINK to user
        deal(link, user, USER_LINK_BALANCE);

        /// @dev deploy CompliantLogic implementation
        logic = new LogicWrapper(address(compliantProxy));

        /// @dev set default gas limit
        defaultGasLimit = compliantRouter.getDefaultGasLimit();
    }

    /// @notice Empty test function to ignore file in coverage report
    function test_baseTest() public {}

    /*//////////////////////////////////////////////////////////////
                                UTILITY
    //////////////////////////////////////////////////////////////*/
    /// @dev set the user to compliant
    function _setUserToCompliant(address _user) internal {
        MockEverestConsumer(everest).setLatestFulfilledRequest(
            false, true, true, msg.sender, _user, uint40(block.timestamp)
        );
    }

    /// @dev set the user to pending request
    function _setUserPendingRequest(address logicContract, uint64 gasLimit) internal {
        uint256 amount = compliantRouter.getFee();
        bytes memory data = abi.encode(user, logicContract, gasLimit);
        vm.prank(user);
        LinkTokenInterface(link).transferAndCall(address(compliantProxy), amount, data);

        // will probably need a function like Everest's getLatestRequestId()
        // bytes32 requestId;
        bytes32 requestId = bytes32(uint256(uint160(user)));

        (, bytes memory retData) =
            address(compliantProxy).call(abi.encodeWithSignature("getPendingRequest(bytes32)", requestId));
        CompliantRouter.PendingRequest memory request = abi.decode(retData, (CompliantRouter.PendingRequest));
        assertTrue(request.isPending);
    }

    /// @dev register Chainlink log trigger automation
    function _registerAutomation(address upkeepContract, address triggerContract) internal returns (uint256) {
        uint256 linkAmount = 3e18;
        deal(link, deployer, linkAmount);

        LogTriggerConfig memory logTrigger = LogTriggerConfig({
            contractAddress: triggerContract,
            filterSelector: 2, // Filter only on topic 1 (_revealer)
            topic0: keccak256("Fulfilled(bytes32,address,address,uint8,uint40)"),
            topic1: bytes32(uint256(uint160(upkeepContract))),
            topic2: bytes32(0),
            topic3: bytes32(0)
        });

        RegistrationParams memory params = RegistrationParams({
            name: "",
            encryptedEmail: hex"",
            upkeepContract: upkeepContract,
            gasLimit: 5000000,
            adminAddress: msg.sender,
            triggerType: 1, // log trigger
            checkData: hex"",
            triggerConfig: abi.encode(logTrigger),
            offchainConfig: hex"",
            amount: uint96(linkAmount)
        });

        /// @dev prank registrar owner to enable automatic log trigger registrations
        /// @notice this is needed because automatic log trigger registrations are not enabled for all on mainnet
        vm.prank(IAutomationRegistrar(registrar).owner());
        /// 1 = log trigger automation, 2 = ENABLED_ALL
        IAutomationRegistrar(registrar).setTriggerConfig(1, 2, type(uint32).max);

        vm.prank(deployer);
        LinkTokenInterface(link).approve(registrar, linkAmount);
        vm.prank(deployer);
        return IAutomationRegistrar(registrar).registerUpkeep(params);
    }
}
