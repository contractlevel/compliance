// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {console2} from "forge-std/Test.sol";
import {Handler} from "./Handler.t.sol";
import {CompliantRouter} from "../../src/CompliantRouter.sol";
import {
    BaseTest,
    Vm,
    LinkTokenInterface,
    HelperConfig,
    InitialImplementation,
    MockEverestConsumer,
    CompliantProxy,
    ProxyAdmin,
    ITransparentUpgradeableProxy,
    MockAutomationRegistry,
    LogicWrapper
} from "../BaseTest.t.sol";
import {IEverestConsumer} from "@everest/contracts/interfaces/IEverestConsumer.sol";
import {IAutomationRegistryConsumer} from
    "@chainlink/contracts/src/v0.8/automation/interfaces/IAutomationRegistryConsumer.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {LogicWrapperRevert} from ".././wrappers/LogicWrapperRevert.sol";

contract Invariant is StdInvariant, BaseTest {
    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @dev initial value returned by registry.getMinBalance()
    uint96 internal constant AUTOMATION_MIN_BALANCE = 1e17;

    /// @dev contract handling calls to Compliant
    Handler internal handler;
    /// @dev passed to handler as example of reverting logic implementation
    LogicWrapperRevert internal logicRevert;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() public override {
        /// @dev get Mock deployments for local testing from config
        HelperConfig config = new HelperConfig();
        address everestAddress;
        (everestAddress, link, linkUsdFeed, registry,, forwarder) = config.activeNetworkConfig();
        everest = MockEverestConsumer(everestAddress);

        /// @dev deploy InitialImplementation
        InitialImplementation initialImplementation = new InitialImplementation();

        /// @dev record logs to get proxyAdmin contract address
        vm.recordLogs();

        /// @dev deploy CompliantProxy
        compliantProxy = new CompliantProxy(address(initialImplementation), proxyDeployer);

        /// @dev get proxyAdmin contract address from logs
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventSignature = keccak256("AdminChanged(address,address)");
        address proxyAdmin;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSignature) {
                (, proxyAdmin) = abi.decode(logs[i].data, (address, address));
            }
        }

        /// @dev register automation
        upkeepId = 1;

        /// @dev deploy Compliant
        vm.prank(deployer);
        compliantRouter =
            new CompliantRouter(address(everest), link, linkUsdFeed, forwarder, upkeepId, address(compliantProxy));

        /// @dev upgradeToAndCall - set Compliant to new implementation and initialize deployer to owner
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

        /// @dev set automation min balance
        MockAutomationRegistry(registry).setMinBalance(AUTOMATION_MIN_BALANCE);

        //-----------------------------------------------------------------------------------------------

        /// @dev deploy CompliantLogic implementation
        logic = new LogicWrapper(address(compliantProxy));
        logicRevert = new LogicWrapperRevert(address(compliantProxy));

        /// @dev set default gas limit
        defaultGasLimit = compliantRouter.getDefaultGasLimit();

        //-----------------------------------------------------------------------------------------------

        /// @dev deploy handler
        handler = new Handler(
            compliantRouter,
            address(compliantProxy),
            deployer,
            link,
            forwarder,
            address(everest),
            address(proxyAdmin),
            registry,
            upkeepId,
            logic,
            logicRevert
        );

        /// @dev define appropriate function selectors
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = Handler.sendRequest.selector;
        selectors[1] = Handler.externalImplementationCalls.selector;
        selectors[2] = Handler.changeFeeVariables.selector;
        selectors[3] = Handler.withdrawFees.selector;

        /// @dev target handler and appropriate function selectors
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetContract(address(handler));

        excludeSender(address(proxyAdmin));
    }

    /*//////////////////////////////////////////////////////////////
                               INVARIANTS
    //////////////////////////////////////////////////////////////*/
    // Proxy Protection:
    /// @dev no direct calls (that change state) to the proxy should succeed
    function invariant_onlyProxy_noDirectCallsSucceed() public view {
        assertEq(
            handler.g_directCallSuccesses(),
            0,
            "Invariant violated: Direct calls to implementation contract should never succeed."
        );
    }

    /// @dev all direct calls (that change state) to the proxy should revert
    function invariant_onlyProxy_directCallsRevert() public view {
        assertEq(
            handler.g_directImplementationCalls(),
            handler.g_directCallReverts(),
            "Invariant violated: All direct calls to implementation contract should revert."
        );
    }

    // Pending Request Management:
    /// @dev pending requests should only be true whilst waiting for Chainlink Automation to be fulfilled
    function invariant_pendingRequest() public {
        handler.forEachRequestId(this.checkPendingStatusForRequestId);
    }

    function checkPendingStatusForRequestId(bytes32 requestId) external {
        (, bytes memory retData) =
            address(compliantProxy).call(abi.encodeWithSignature("getPendingRequest(bytes32)", requestId));
        CompliantRouter.PendingRequest memory request = abi.decode(retData, (CompliantRouter.PendingRequest));

        assertEq(
            request.isPending,
            handler.g_pendingRequests(requestId),
            "Invariant violated: Pending request should only be true whilst waiting for Chainlink Automation to be fulfilled."
        );
    }

    // Fees Accounting:
    /// @dev fees available for owner to withdraw should always equal cumulative LINK earned minus any already withdrawn
    function invariant_feesAccounting() public {
        (, bytes memory retData) = address(compliantProxy).call(abi.encodeWithSignature("getCompliantFeesToWithdraw()"));
        uint256 fees = abi.decode(retData, (uint256));

        assertEq(
            fees,
            handler.g_totalFeesEarned() - handler.g_totalFeesWithdrawn(),
            "Invariant violated: Compliant Protocol fees available to withdraw should be total earned minus total withdrawn."
        );
    }

    // KYC Status Consistency:
    /// @dev A user marked as compliant (_isCompliant(user)) must have their latest fulfilled KYC request isKYCUser = true.
    function invariant_compliantStatusIntegrity() public {
        handler.forEachUser(this.checkCompliantStatusForUser);
    }

    function checkCompliantStatusForUser(address user) external {
        (, bytes memory retData) =
            address(compliantProxy).call(abi.encodeWithSignature("getIsCompliant(address)", user));
        bool isCompliant = abi.decode(retData, (bool));

        IEverestConsumer.Request memory request = IEverestConsumer(address(everest)).getLatestFulfilledRequest(user);

        assertEq(
            isCompliant,
            request.isKYCUser,
            "Invariant violated: Compliant status returned by contract should be the same as latest fulfilled Everest request."
        );
    }

    // Fee Calculation:
    /// @dev the fee for requests should always be the sum of compliantFee, everestFee and upkeep minBalance.
    function invariant_feeCalculation() public {
        (, bytes memory retData) = address(compliantProxy).call(abi.encodeWithSignature("getFee()"));
        uint256 fee = abi.decode(retData, (uint256));

        uint256 oraclePayment = IEverestConsumer(address(everest)).oraclePayment();
        uint256 minBalance = IAutomationRegistryConsumer(registry).getMinBalance(upkeepId);
        uint256 expectedFee = oraclePayment + minBalance + compliantRouter.getCompliantFee();

        assertEq(
            fee,
            expectedFee,
            "Invariant violated: Fee for a request with Automation should always equal the Compliant, Everest, and upkeep minBalance."
        );
    }

    // Compliant Logic:
    /// @dev assert automated compliant restricted logic changes state correctly
    function invariant_compliantLogic_stateChange() public view {
        uint256 incrementedValue = logic.getIncrementedValue();

        assertEq(
            incrementedValue,
            handler.g_incrementedValue(),
            "Invariant violated: Compliant restricted logic state change should be consistent."
        );
    }

    // Forwarder Protection:
    /// @dev only the forwarder can call performUpkeep
    function invariant_onlyForwarder_canCall_performUpkeep() public {
        handler.forEachUser(this.checkForwarderCanCallPerformUpkeep);
    }

    function checkForwarderCanCallPerformUpkeep(address user) external {
        bytes32 requestId = keccak256(abi.encodePacked(everest, handler.g_requestsMade()));

        bytes memory performData = abi.encode(requestId, user, address(logic), defaultGasLimit, true);

        vm.prank(forwarder);
        (bool success,) = address(compliantProxy).call(abi.encodeWithSignature("performUpkeep(bytes)", performData));
        assertTrue(success, "Invariant violated: Forwarder should be able to call performUpkeep");

        vm.assume(user != forwarder);
        vm.prank(user);
        (success,) = address(compliantProxy).call(abi.encodeWithSignature("performUpkeep(bytes)", performData));
        assertFalse(success, "Invariant violated: Non-forwarder should not be able to call performUpkeep");
    }

    // Event Consistency:
    /// @dev assert CompliantStatusRequested event is emitted for every request
    function invariant_eventConsistency_compliantStatusRequested() public view {
        assertEq(
            handler.g_requestedEventsEmitted(),
            handler.g_requestsMade(),
            "Invariant violated: A CompliantStatusRequested event should be emitted for every request."
        );
    }

    /// @dev every KYC status request emits a CompliantStatusRequested event with the correct everestRequestId and user.
    function invariant_eventConsistency_compliantStatusRequested_requestId() public {
        handler.forEachUser(this.checkCompliantStatusRequestedEvent);
    }

    function checkCompliantStatusRequestedEvent(address user) external view {
        uint256 nonce = handler.g_requestedUserToRequestNonce(user);
        bytes32 expectedRequestId = keccak256(abi.encodePacked(everest, nonce));

        if (handler.g_requestedUsers(user)) {
            assertEq(
                expectedRequestId,
                handler.g_requestedEventRequestId(user),
                "Invariant violated: CompliantStatusRequested event params should emit correct requestId and user."
            );
        } else {
            assertEq(
                handler.g_requestedEventRequestId(user),
                0,
                "Invariant violated: A user who hasn't been requested should not have been emitted."
            );
        }
    }

    /// @dev assert CompliantStatusFulfilled event emitted for fulfilled requests
    function invariant_eventConsistency_compliantStatusFulfilled() public view {
        assertEq(
            handler.g_compliantFulfilledEventsEmitted(),
            handler.g_requestsFulfilled(),
            "Invariant violated: A CompliantStatusFulfilled event should be emitted for every request fulfilled."
        );
    }

    /// @dev CompliantStatusFulfilled event should emit the correct isCompliant status
    function invariant_eventConsistency_compliantStatusFulfilled_isCompliant() public {
        handler.forEachUser(this.checkFulfilledRequestEventsCompliantStatus);
    }

    function checkFulfilledRequestEventsCompliantStatus(address user) external view {
        assertEq(
            handler.g_compliantFulfilledEventIsCompliant(user),
            handler.g_everestFulfilledEventIsCompliant(user),
            "Invariant violated: Compliant status should be the same in Compliant Fulfilled event as Everest Fulfilled."
        );
    }

    /// @dev CompliantStatusFulfilled event should emit the correct requestId
    function invariant_eventConsistency_compliantStatusFulfilled_requestId() public {
        handler.forEachUser(this.checkFulfilledRequestEventsRequestId);
    }

    function checkFulfilledRequestEventsRequestId(address user) external view {
        if (handler.g_fulfilledUsers(user)) {
            assertEq(
                handler.g_everestFulfilledEventRequestId(user),
                handler.g_compliantFulfilledEventRequestId(user),
                "Invariant violated: Request ID should be the same in automated Compliant Fulfilled event as Everest Fulfilled."
            );
        }
    }

    /// @dev withdrawFees should emit a FeesWithdrawn event
    function invariant_eventConsistency_withdrawFees() public view {
        assertEq(
            handler.g_feesWithdrawnEventsEmitted(),
            handler.g_withdrawFeesCalls(),
            "Invariant violated: withdrawFees should emit a FeesWithdrawn event."
        );
    }

    /// @dev FeesWithdrawn event should emit the correct amount
    function invariant_eventConsistency_withdrawFees_amount() public {
        assertEq(
            handler.g_totalFeesWithdrawn(),
            handler.g_totalFeesWithdrawnEmittedByEvent(),
            "Invariant violated: FeesWithdrawn event should emit the correct amount."
        );
    }

    // Fee Transfer Validity:
    /// @dev LINK balance of the contract should decrease by the exact amount transferred to the owner in withdrawFees
    function invariant_linkBalanceIntegrity() public view {
        uint256 balance = LinkTokenInterface(link).balanceOf(address(compliantProxy));

        assertEq(
            balance,
            handler.g_totalFeesEarned() - handler.g_totalFeesWithdrawn(),
            "Invariant violated: LINK balance should decrease by the exact amount transferred to the owner in withdrawFees."
        );
    }

    // Approvals:
    /// @dev LINK approvals to everest and the registry must match the required fees for the respective operations
    function invariant_approval_everest() public view {
        assertEq(
            handler.g_lastApprovalEverest(),
            handler.g_lastEverestFee(),
            "Invariant violated: Amount approved for Everest spending must match it's required fee."
        );
    }

    function invariant_approval_automation() public view {
        assertEq(
            handler.g_lastApprovalRegistry(),
            handler.g_lastAutomationFee(),
            "Invariant violated: Amount approved for Automation registry spending must match upkeepId minBalance."
        );
    }

    // Ownership Management:
    /// @dev only owner should be able to call withdrawFees
    function invariant_onlyOwner_canCall_withdrawFees() public {
        vm.prank(owner);
        (bool success,) = address(compliantProxy).call(abi.encodeWithSignature("withdrawFees()"));
        assertTrue(success, "Invariant violated: Owner should be able to call withdrawFees");

        handler.forEachUser(this.checkOwnerCanCallWithdrawFees);
    }

    function checkOwnerCanCallWithdrawFees(address user) external {
        vm.assume(user != owner);
        vm.prank(user);
        (bool success,) = address(compliantProxy).call(abi.encodeWithSignature("withdrawFees()"));
        assertFalse(success, "Invariant violated: Non-owner should not be able to call withdrawFees.");
    }

    // Initialization Protection:
    /// @dev initialize() can only be called once, and should revert when called after
    function invariant_initialize_reverts() public {
        handler.forEachUser(this.checkInitializeReverts);
    }

    function checkInitializeReverts(address user) external {
        vm.prank(user);
        (bool success,) = address(compliantProxy).call(abi.encodeWithSignature("initialize()"));
        assertFalse(success, "Invariant violated: Initialize should not be callable a second time.");
    }

    // Upkeep Execution:
    /// @dev Requests should add funds to the Chainlink registry via registry.addFunds
    function invariant_requests_addFundsToRegistry() public view {
        assertEq(
            LinkTokenInterface(link).balanceOf(registry),
            handler.g_linkAddedToRegistry(),
            "Invariant violated: Automated requests should add funds to Chainlink Automation Registry."
        );
    }

    //  NOTE: THIS WOULD REQUIRE LOCAL CHAINLINK AUTOMATION SIMULATOR
    //  performUpkeep should only process requests where checkLog indicates that upkeepNeeded is true.

    // Gas Limit:
    /// @dev Less than minimum or default gas limit should not write to storage
    function invariant_gasLimit_noStorageWrite() public {
        handler.forEachRequestId(this.checkGasLimitStorage);
    }

    function checkGasLimitStorage(bytes32 requestId) external {
        (, bytes memory retData) =
            address(compliantProxy).call(abi.encodeWithSignature("getPendingRequest(bytes32)", requestId));
        CompliantRouter.PendingRequest memory request = abi.decode(retData, (CompliantRouter.PendingRequest));

        if (
            handler.g_requestIdToGasLimit(requestId) == defaultGasLimit
                || handler.g_requestIdToGasLimit(requestId) < compliantRouter.getMinGasLimit()
        ) {
            assertEq(
                request.gasLimit,
                0,
                "Invariant violated: Less than minimum or default gas limit should not write to storage."
            );
        }
    }

    // we want to assert that our performUpkeep is always a success when the logic implementation reverts
}

// CompliantLogicExecutionFailed
// will probably need a bool isLogic passed to everywhere address(logic) is
