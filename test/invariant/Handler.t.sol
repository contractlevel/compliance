// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2, Vm} from "forge-std/Test.sol";
import {CompliantRouter} from "../../src/CompliantRouter.sol";
import {MockEverestConsumer} from "../mocks/MockEverestConsumer.sol";
import {MockAutomationRegistry} from "../mocks/MockAutomationRegistry.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {IEverestConsumer} from "@everest/contracts/interfaces/IEverestConsumer.sol";
import {IAutomationRegistryConsumer} from
    "@chainlink/contracts/src/v0.8/automation/interfaces/IAutomationRegistryConsumer.sol";
import {LogicWrapper} from "../wrappers/LogicWrapper.sol";
import {LogicWrapperRevert} from "../wrappers/LogicWrapperRevert.sol";

contract Handler is Test {
    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;

    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @dev compliant contract being handled
    CompliantRouter public compliantRouter;
    /// @dev compliant proxy being handled
    address public compliantProxy;
    /// @dev deployer
    address public deployer;
    /// @dev LINK token
    address public link;
    /// @dev Chainlink Automation forwarder
    address public forwarder;
    /// @dev Everest Chainlink Consumer
    address public everest;
    /// @dev ProxyAdmin contract
    address public proxyAdmin;
    /// @dev Chainlink Automation Registry
    address public registry;
    /// @dev Chainlink Automation UpkeepId
    uint256 public upkeepId;
    /// @dev CompliantLogic wrapper implementation
    LogicWrapper public logic;
    /// @dev CompliantLogic reverting implementation
    LogicWrapperRevert public logicRevert;
    /// @dev DEFAULT_GAS_LIMIT for logic callback
    uint64 public defaultGasLimit;

    /// @dev track the users in the system (requestedAddresses)
    EnumerableSet.AddressSet internal users;
    /// @dev track the requestIds in the system
    EnumerableSet.Bytes32Set internal requestIds;

    /// @dev ghost to track direct calls to Compliant implementation
    uint256 public g_directImplementationCalls;
    /// @dev ghost to track direct calls to Compliant implementation that succeeded
    uint256 public g_directCallSuccesses;
    /// @dev ghost to track direct calls to Compliant implementation that have failed
    uint256 public g_directCallReverts;

    /// @dev ghost to track total Compliant protocol fees that have been paid by users
    uint256 public g_totalFeesEarned;
    /// @dev ghost to track total fees that have been withdrawn
    uint256 public g_totalFeesWithdrawn;

    /// @dev ghost to track number of times compliant restricted logic executed with automation
    uint256 public g_incrementedValue;

    /// @dev ghost to increment every time CompliantStatusFulfilled contains compliant
    uint256 public g_fulfilledRequestIsCompliant;
    /// @dev ghost to increment every time CompliantCheckPassed() event is emitted for automated requests
    uint256 public g_automatedCompliantCheckPassed;

    /// @dev ghost to track params emitted by CompliantStatusRequested(bytes32,address,address) event
    mapping(address user => bytes32 requestId) public g_requestedEventRequestId;
    /// @dev ghost to track if a user's compliance status has been requested
    mapping(address user => bool requested) public g_requestedUsers;

    /// @dev ghost to track amount of requests made
    uint256 public g_requestsMade;
    /// @dev ghost to track amount of CompliantStatusRequested(bytes32,address,address) events emitted
    uint256 public g_requestedEventsEmitted;
    /// @dev ghost to track amount of requests fulfilled
    uint256 public g_requestsFulfilled; // compliant request event
    /// @dev ghost to increment amount of CompliantStatusFulfilled(bytes32,address,address,bool) events emitted
    uint256 public g_compliantFulfilledEventsEmitted;

    /// @dev ghost to increment amount of FeesWithdrawn(uint256) events emitted
    uint256 public g_feesWithdrawnEventsEmitted;
    /// @dev ghost to track total fees withdrawn emitted by FeesWithdrawn(uint256) events
    uint256 public g_totalFeesWithdrawnEmittedByEvent;
    /// @dev ghost to track amount of withdrawFees() calls
    uint256 public g_withdrawFeesCalls;

    /// @dev ghost to increment every time Everest.Fulfilled() event is emitted
    uint256 public g_everestFulfilledEventsEmitted;

    /// @dev ghost to track if request for user's status has been fulfilled
    mapping(address user => bool fulfilled) public g_fulfilledUsers;
    /// @dev ghost to track if fulfilled event from everest marks user as compliant
    mapping(address user => bool isCompliant) public g_everestFulfilledEventIsCompliant;
    /// @dev ghost mapping of user to requestId emitted by Everest.Fulfilled
    mapping(address user => bytes32 everestRequestId) public g_everestFulfilledEventRequestId;
    /// @dev ghost to track if fulfilled event from compliant marks user as compliant
    mapping(address user => bool isCompliant) public g_compliantFulfilledEventIsCompliant;
    /// @dev ghost to track requestId emitted by Compliant KYCStatusRequestFulfilled event
    mapping(address user => bytes32 requestId) public g_compliantFulfilledEventRequestId;

    /// @dev ghost to track last everest fee during request
    uint256 public g_lastEverestFee;
    /// @dev ghost to track last minBalance for Automation during request
    uint256 public g_lastAutomationFee;
    /// @dev ghost to track last amount emitted by Everest approval event
    uint256 public g_lastApprovalEverest;
    /// @dev ghost to track last amount emitted by Automation registry approval event
    uint256 public g_lastApprovalRegistry;

    /// @dev ghost to track amount of LINK sent to registry
    uint256 public g_linkAddedToRegistry;

    /// @dev ghost to track withdrawable admin fees
    uint256 public g_compliantFeesInLink;
    /// @dev ghost to track requestedAddresses to compliant status
    mapping(address requestedAddress => bool isCompliant) public g_requestedAddressToStatus;
    /// @dev ghost to track pending requests
    mapping(bytes32 requestId => bool isPending) public g_pendingRequests;
    /// @dev ghost to track requestId to user
    mapping(bytes32 requestId => address user) public g_requestIdToUser;
    /// @dev ghost to track requestId to gasLimit
    mapping(bytes32 requestId => uint64 gasLimit) public g_requestIdToGasLimit;

    /// @dev ghost to track the requestId to whether the request is to valid logic implementation
    // do we need this? is this the right kind of ghost? what do we want to track about valid logic implementation use?
    mapping(bytes32 requestId => bool isLogic) public g_requestIsLogic;

    /// @dev ghost to track the nonce used to create a requestId
    mapping(address user => uint256 requestNonce) public g_requestedUserToRequestNonce;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(
        CompliantRouter _compliantRouter,
        address _compliantProxy,
        address _deployer,
        address _link,
        address _forwarder,
        address _everest,
        address _proxyAdmin,
        address _registry,
        uint256 _upkeepId,
        LogicWrapper _logic,
        LogicWrapperRevert _logicRevert
    ) {
        compliantRouter = _compliantRouter;
        compliantProxy = _compliantProxy;
        deployer = _deployer;
        link = _link;
        forwarder = _forwarder;
        everest = _everest;
        proxyAdmin = _proxyAdmin;
        registry = _registry;
        upkeepId = _upkeepId;
        logic = _logic;
        logicRevert = _logicRevert;
        defaultGasLimit = compliantRouter.getDefaultGasLimit();
    }

    /*//////////////////////////////////////////////////////////////
                                EXTERNAL
    //////////////////////////////////////////////////////////////*/
    /// @dev simulate onTokenTransfer or requestKycStatus
    function sendRequest(uint256 addressSeed, bool isCompliant, bool isOnTokenTransfer, bool isLogic, uint64 gasLimit)
        public
    {
        /// @dev bound gasLimit
        gasLimit = uint64(bound(gasLimit, 0, compliantRouter.getMaxGasLimit()));

        /// @dev start request by getting a user and dealing them appropriate amount of link
        (address user, uint256 amount) = _startRequest(addressSeed, isCompliant);
        users.add(user);

        address logicImplementation;
        if (isLogic) logicImplementation = address(logic);
        else logicImplementation = address(logicRevert);

        /// @dev record logs of the request (and simulated Everest fulfillment)
        vm.recordLogs();

        /// @dev send request with isOnTokenTransfer or requestKycStatus
        if (isOnTokenTransfer) {
            /// @dev create calldata for transferAndCall request
            bytes memory data = abi.encode(user, logicImplementation, gasLimit);
            /// @dev send request with onTokenTransfer
            vm.startPrank(user);
            bool success =
                LinkTokenInterface(compliantRouter.getLink()).transferAndCall(address(compliantProxy), amount, data);
            require(success, "transferAndCall in handler failed");
            vm.stopPrank();
        } else {
            /// @dev approve compliantProxy to spend link
            vm.startPrank(user);
            LinkTokenInterface(compliantRouter.getLink()).approve(address(compliantProxy), amount);
            /// @dev requestKycStatus
            (bool success,) = address(compliantProxy).call(
                abi.encodeWithSignature("requestKycStatus(address,address,uint64)", user, logicImplementation, gasLimit)
            );
            require(success, "delegate call in handler to requestKycStatus() failed");
            vm.stopPrank();
        }

        /// @dev get the requestId from recorded logs and update relevant ghosts and simulated Everest fulfill
        bytes32 requestId = _handleRequestLogs();

        /// @dev update relevant ghosts for request
        _updateRequestGhosts(requestId, user, isLogic, gasLimit);

        /// @dev record logs again
        vm.recordLogs();

        /// @dev simulate automation with performUpkeep
        _performUpkeep(user, logicImplementation, isCompliant, isLogic, gasLimit);

        /// @dev handle logs for performUpkeep
        _handlePerformUpkeepLogs();
    }

    /// @dev onlyOwner
    function withdrawFees(uint256 addressSeed, bool isCompliant, bool isOnTokenTransfer, bool isLogic, uint64 gasLimit)
        public
    {
        if (g_compliantFeesInLink == 0) {
            sendRequest(addressSeed, isCompliant, isOnTokenTransfer, isLogic, gasLimit);
        } else {
            /// @dev getCompliantFeesToWithdraw and add it to ghost tracker
            (, bytes memory retData) =
                address(compliantProxy).call(abi.encodeWithSignature("getCompliantFeesToWithdraw()"));
            uint256 fees = abi.decode(retData, (uint256));

            /// @dev record logs
            vm.recordLogs();

            vm.prank(compliantRouter.owner());
            (bool success,) = address(compliantProxy).call(abi.encodeWithSignature("withdrawFees()"));
            require(success, "delegate call in handler to withdrawFees() failed");

            g_totalFeesWithdrawn += fees;
            g_compliantFeesInLink = 0;
            g_withdrawFeesCalls += 1;

            _handleWithdrawFeeLogs();
        }
    }

    /// @dev onlyProxy
    function externalImplementationCalls(uint256 divisor, uint256 addressSeed) public {
        /// @dev increment ghost
        g_directImplementationCalls++;

        /// @dev get revealer and requestedAddress
        addressSeed = bound(addressSeed, 1, type(uint256).max - 1);
        address user = _seedToAddress(addressSeed);

        /// @dev make direct call to one of external functions
        uint256 choice = divisor % 4;
        if (choice == 0) {
            _directOnTokenTransfer(user);
        } else if (choice == 1) {
            _directRequestKycStatus(user);
        } else if (choice == 2) {
            _directWithdrawFees();
        } else if (choice == 3) {
            _directInitialize(user);
        } else {
            revert("Invalid choice");
        }
    }

    function changeFeeVariables(uint256 oraclePayment, uint256 minBalance) public {
        uint256 minValue = 1e15;
        uint256 maxValue = 1e19;
        oraclePayment = bound(oraclePayment, minValue, maxValue);
        minBalance = bound(minBalance, minValue, maxValue);
        MockEverestConsumer(everest).setOraclePayment(oraclePayment);
        MockAutomationRegistry(registry).setMinBalance(uint96(minBalance));
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/
    /// @dev onlyForwarder
    function _performUpkeep(
        address requestedAddress,
        address logicImplementation,
        bool isCompliant,
        bool isLogic,
        uint64 gasLimit
    ) internal {
        if (gasLimit < compliantRouter.getMinGasLimit()) gasLimit = compliantRouter.getDefaultGasLimit();

        bytes32 requestId = keccak256(abi.encodePacked(everest, g_requestsMade));
        bytes memory performData = abi.encode(requestId, requestedAddress, logicImplementation, gasLimit, isCompliant);

        vm.prank(forwarder);
        (bool success,) = address(compliantProxy).call(abi.encodeWithSignature("performUpkeep(bytes)", performData));
        require(success, "delegate call in handler to performUpkeep() failed");

        _updatePerformUpkeepGhosts(requestId, requestedAddress, isCompliant, isLogic);
    }

    function _handleOnlyProxyError(bytes memory error) internal {
        g_directCallReverts++;

        bytes4 selector;
        assembly {
            selector := mload(add(error, 32))
        }
        assertEq(selector, bytes4(keccak256("CompliantRouter__OnlyProxy()")));
    }

    function _startRequest(uint256 addressSeed, bool isCompliant) internal returns (address, uint256) {
        /// @dev create a user
        address user = _seedToAddress(addressSeed);
        require(user != proxyAdmin && user != compliantProxy, "Invalid address used.");
        /// @dev set the Everest status for the request
        _setEverestStatus(user, isCompliant);
        /// @dev deal link to user
        uint256 amount = _dealLink(user);

        return (user, amount);
    }

    function _updateRequestGhosts(bytes32 requestId, address user, bool isLogic, uint64 gasLimit) internal {
        /// @dev set request to pending
        g_pendingRequests[requestId] = true;
        g_requestIdToUser[requestId] = user;
        g_requestIdToGasLimit[requestId] = gasLimit;

        g_linkAddedToRegistry += IAutomationRegistryConsumer(registry).getMinBalance(upkeepId);

        /// @dev update totalFeesEarned ghost
        g_totalFeesEarned +=
            compliantRouter.getFee() - IEverestConsumer(everest).oraclePayment() - compliantRouter.getAutomationFee();

        /// @dev increment requests made
        g_requestsMade++;
        g_requestedUserToRequestNonce[user] = g_requestsMade;

        /// @dev update last external fees
        g_lastEverestFee = IEverestConsumer(everest).oraclePayment();
        g_lastAutomationFee = IAutomationRegistryConsumer(registry).getMinBalance(upkeepId);

        /// @dev map the requestId to whether the request is to valid logic implementation
        g_requestIsLogic[requestId] = isLogic;
    }

    function _updatePerformUpkeepGhosts(bytes32 requestId, address user, bool isCompliant, bool isLogic) internal {
        /// @dev increment
        if (isCompliant && isLogic) g_incrementedValue++;

        g_pendingRequests[requestId] = false;
        g_fulfilledUsers[user] = true;
        g_requestsFulfilled++;
    }

    function _handleRequestLogs() internal returns (bytes32) {
        bytes32 compliantStatusRequested = keccak256("CompliantStatusRequested(bytes32,address,address)");
        bytes32 everestFulfilled = keccak256("Fulfilled(bytes32,address,address,uint8,uint40)");
        bytes32 approval = keccak256("Approval(address,address,uint256)");

        bytes32 requestId;

        Vm.Log[] memory logs = vm.getRecordedLogs();

        for (uint256 i = 0; i < logs.length; i++) {
            /// @dev handle CompliantStatusRequested() event params and ghosts
            if (logs[i].topics[0] == compliantStatusRequested) {
                bytes32 emittedRequestId = logs[i].topics[1];
                address emittedUser = address(uint160(uint256(logs[i].topics[2])));

                g_requestedEventRequestId[emittedUser] = emittedRequestId;
                g_requestedUsers[emittedUser] = true;
                g_requestedEventsEmitted++;

                requestId = emittedRequestId;
                requestIds.add(requestId);
            }

            /// @dev handle Everest.Fulfilled() event params and ghost
            if (logs[i].topics[0] == everestFulfilled) {
                address revealee = address(uint160(uint256(logs[i].topics[2])));
                (bytes32 everestRequestId, IEverestConsumer.Status status,) =
                    abi.decode(logs[i].data, (bytes32, IEverestConsumer.Status, uint40));

                g_everestFulfilledEventRequestId[revealee] = everestRequestId;
                g_everestFulfilledEventIsCompliant[revealee] = (status == IEverestConsumer.Status.KYCUser);
                g_everestFulfilledEventsEmitted++;
            }

            /// @dev handle Approval() event
            if (logs[i].topics[0] == approval) {
                address spender = address(uint160(uint256(logs[i].topics[2])));
                uint256 value = abi.decode(logs[i].data, (uint256));

                if (spender == everest) {
                    g_lastApprovalEverest = value;
                }
                if (spender == registry) {
                    g_lastApprovalRegistry = value;
                }
            }
        }

        return requestId;
    }

    function _handlePerformUpkeepLogs() internal {
        bytes32 compliantStatusFulfilled = keccak256("CompliantStatusFulfilled(bytes32,address,address,bool)");

        Vm.Log[] memory logs = vm.getRecordedLogs();

        address user;

        for (uint256 i = 0; i < logs.length; i++) {
            /// @dev handle CompliantStatusFulfilled() event params and ghost
            if (logs[i].topics[0] == compliantStatusFulfilled) {
                bytes32 emittedRequestId = logs[i].topics[1];
                user = address(uint160(uint256(logs[i].topics[2])));
                g_compliantFulfilledEventRequestId[user] = emittedRequestId;

                /// @dev if isCompliant is true, increment ghost value
                bool emittedBool = abi.decode(logs[i].data, (bool));
                if (emittedBool) g_fulfilledRequestIsCompliant++;
                g_compliantFulfilledEventIsCompliant[user] = emittedBool;

                g_compliantFulfilledEventsEmitted++;
            }
        }
    }

    function _handleWithdrawFeeLogs() internal {
        bytes32 feesWithdrawn = keccak256("FeesWithdrawn(uint256)");

        Vm.Log[] memory logs = vm.getRecordedLogs();

        for (uint256 i = 0; i < logs.length; i++) {
            /// @dev handle FeesWithdrawn() event params and ghost
            if (logs[i].topics[0] == feesWithdrawn) {
                uint256 amountWithdrawn = uint256(logs[i].topics[1]);

                g_totalFeesWithdrawnEmittedByEvent += amountWithdrawn;

                g_feesWithdrawnEventsEmitted++;
            }
        }
    }

    function _directOnTokenTransfer(address user) internal {
        uint256 amount = _dealLink(user);

        bytes memory data = abi.encode(user, address(logic));

        vm.prank(user);
        try LinkTokenInterface(link).transferAndCall(address(compliantRouter), amount, data) {
            g_directCallSuccesses++;
        } catch (bytes memory error) {
            _handleOnlyProxyError(error);
        }
    }

    function _directRequestKycStatus(address user) internal {
        uint256 amount = compliantRouter.getFee();
        deal(link, user, amount);

        vm.prank(user);
        try compliantRouter.requestKycStatus(user, address(logic), defaultGasLimit) {
            g_directCallSuccesses++;
        } catch (bytes memory error) {
            _handleOnlyProxyError(error);
        }
    }

    function _directWithdrawFees() internal {
        try compliantRouter.withdrawFees() {
            g_directCallSuccesses++;
        } catch (bytes memory error) {
            _handleOnlyProxyError(error);
        }
    }

    function _directInitialize(address initialOwner) internal {
        try compliantRouter.initialize(initialOwner) {
            g_directCallSuccesses++;
        } catch (bytes memory error) {
            _handleOnlyProxyError(error);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                UTILITY
    //////////////////////////////////////////////////////////////*/
    /// @dev helper function for looping through users in the system
    function forEachUser(function(address) external func) external {
        if (users.length() == 0) return;

        for (uint256 i; i < users.length(); ++i) {
            func(users.at(i));
        }
    }

    /// @dev helper function for looping through requestIds in the system
    function forEachRequestId(function(bytes32) external func) external {
        if (requestIds.length() == 0) return;

        for (uint256 i; i < requestIds.length(); ++i) {
            func(requestIds.at(i));
        }
    }

    /// @dev convert a seed to an address
    function _seedToAddress(uint256 addressSeed) internal view returns (address seedAddress) {
        uint160 boundInt = uint160(bound(addressSeed, 1, type(uint160).max));
        seedAddress = address(boundInt);
        if (seedAddress == compliantProxy) {
            addressSeed++;
            boundInt = uint160(bound(addressSeed, 1, type(uint160).max));
            seedAddress = address(boundInt);
            if (seedAddress == proxyAdmin) {
                addressSeed++;
                boundInt = uint160(bound(addressSeed, 1, type(uint160).max));
                seedAddress = address(boundInt);
            }
        }
        vm.assume(seedAddress != proxyAdmin);
        vm.assume(seedAddress != compliantProxy);
        return seedAddress;
    }

    /// @dev create a user address for calling and passing to requestKycStatus or onTokenTransfer
    function _createOrGetUser(uint256 addressSeed) internal returns (address user) {
        if (users.length() == 0) {
            user = _seedToAddress(addressSeed);
            users.add(user);

            return user;
        } else {
            user = _indexToUser(addressSeed);

            return user;
        }
    }

    /// @dev convert an index to an existing user
    function _indexToUser(uint256 addressIndex) internal view returns (address) {
        return users.at(bound(addressIndex, 0, users.length() - 1));
    }

    /// @dev set/fuzz the everest status of a requestedAddress
    function _setEverestStatus(address user, bool isCompliant) internal {
        MockEverestConsumer(address(compliantRouter.getEverest())).setLatestFulfilledRequest(
            false, isCompliant, isCompliant, address(compliantProxy), user, uint40(block.timestamp)
        );

        g_requestedAddressToStatus[user] = isCompliant;
    }

    /// @dev deal link to revealer to pay for funds and return amount
    function _dealLink(address receiver) internal returns (uint256) {
        uint256 amount = compliantRouter.getFee();

        deal(link, receiver, amount);

        return amount;
    }

    /// @notice Empty test function to ignore file in coverage report
    function test_handler() public {}
}
