// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2, Vm} from "forge-std/Test.sol";
import {Compliant} from "../../src/Compliant.sol";
import {MockEverestConsumer} from "../mocks/MockEverestConsumer.sol";
import {MockAutomationRegistry} from "../mocks/MockAutomationRegistry.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {IEverestConsumer} from "@everest/contracts/interfaces/IEverestConsumer.sol";

contract Handler is Test {
    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    using EnumerableSet for EnumerableSet.AddressSet;

    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @dev compliant contract being handled
    Compliant public compliant;
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

    /// @dev track the users in the system (requestedAddresses)
    EnumerableSet.AddressSet internal users;

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

    /// @dev ghost to track number of times compliant restricted logic manually executed
    uint256 public g_manualIncrement;
    /// @dev ghost to track number of times compliant restricted logic executed with automation
    uint256 public g_automationIncrement;

    /// @dev ghost to increment every time KYCStatusRequestFulfilled contains compliant
    uint256 public g_fulfilledRequestIsCompliant;
    /// @dev ghost to increment every time CompliantCheckPassed() event is emitted for automated requests
    uint256 public g_automatedCompliantCheckPassed;

    /// @dev ghost to track params emitted by KYCStatusRequested(address,bytes32) event
    mapping(address user => bytes32 requestId) public g_requestedEventRequestId;
    /// @dev ghost to track if a user's compliance status has been requested
    mapping(address user => bool requested) public g_requestedUsers;

    /// @dev ghost to track amount of requests made
    uint256 public g_requestsMade;
    /// @dev ghost to track amount of KYCStatusRequested(bytes32,address) events emitted
    uint256 public g_requestedEventsEmitted;
    /// @dev ghost to track amount of requests fulfilled
    uint256 public g_requestsFulfilled; // compliant request event
    /// @dev ghost to increment amount of KYCStatusRequestFulfilled(bytes32,address,bool) events emitted
    uint256 public g_compliantFulfilledEventsEmitted;

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

    /// @dev ghost to track withdrawable admin fees
    uint256 public g_compliantFeesInLink;
    /// @dev ghost to track requestedAddresses to compliant status
    mapping(address requestedAddress => bool isCompliant) public g_requestedAddressToStatus;
    /// @dev ghost to track requestedAddresses to compliant calldata
    mapping(address requestedAddress => bytes compliantCalldata) public g_requestedAddressToCalldata;
    /// @dev ghost to track pending requests
    mapping(address requestedAddress => bool isPending) public g_pendingRequests;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(
        Compliant _compliant,
        address _compliantProxy,
        address _deployer,
        address _link,
        address _forwarder,
        address _everest,
        address _proxyAdmin,
        address _registry
    ) {
        compliant = _compliant;
        compliantProxy = _compliantProxy;
        deployer = _deployer;
        link = _link;
        forwarder = _forwarder;
        everest = _everest;
        proxyAdmin = _proxyAdmin;
        registry = _registry;
    }

    /*//////////////////////////////////////////////////////////////
                                EXTERNAL
    //////////////////////////////////////////////////////////////*/
    /// @dev simulate onTokenTransfer or requestKycStatus
    function sendRequest(
        uint256 addressSeed,
        bool isCompliant,
        bool isAutomation,
        bytes calldata compliantCalldata,
        bool isOnTokenTransfer
    ) public {
        /// @dev start request by getting a user and dealing them appropriate amount of link
        (address user, uint256 amount) = _startRequest(addressSeed, isCompliant, isAutomation);
        users.add(user);

        /// @dev record logs of the request (and simulated Everest fulfillment)
        vm.recordLogs();

        /// @dev send request with isOnTokenTransfer or requestKycStatus
        if (isOnTokenTransfer) {
            /// @dev create calldata for transferAndCall request
            bytes memory data = abi.encode(user, isAutomation, compliantCalldata);
            /// @dev send request with onTokenTransfer
            vm.startPrank(user);
            bool success = compliant.getLink().transferAndCall(address(compliantProxy), amount, data);
            require(success, "transferAndCall in handler failed");
            vm.stopPrank();
        } else {
            /// @dev approve compliantProxy to spend link
            vm.startPrank(user);
            compliant.getLink().approve(address(compliantProxy), amount);
            /// @dev requestKycStatus
            (bool success,) = address(compliantProxy).call(
                abi.encodeWithSignature("requestKycStatus(address,bool,bytes)", user, isAutomation, compliantCalldata)
            );
            require(success, "delegate call in handler to requestKycStatus() failed");
            vm.stopPrank();
        }

        /// @dev update relevant ghosts for request
        _updateRequestGhosts(user, isAutomation, compliantCalldata);

        /// @dev if isAutomation, simulate automation with performUpkeep
        if (isAutomation) {
            _performUpkeep(user, isCompliant);
        }

        /// @dev get recorded logs and update relevant ghosts for requested event and simulated Everest fulfill
        _handleRequestLogs(user);
    }

    function insufficientFeeRequest(
        uint256 addressSeed,
        bool isCompliant,
        bool isAutomation,
        bytes calldata compliantCalldata,
        bool isOnTokenTransfer
    ) public {
        /// @dev start request by getting a user and dealing them appropriate amount of link
        (address user, uint256 amount) = _startRequest(addressSeed, isCompliant, isAutomation);
        users.add(user);

        /// @dev make sure the fee is insufficient by the smallest possible amount
        amount -= 1;

        if (isOnTokenTransfer) {
            bytes memory data = abi.encode(user, isAutomation, compliantCalldata);

            vm.prank(user);
            vm.expectRevert();
            bool success = compliant.getLink().transferAndCall(address(compliantProxy), amount, data);
            require(!success, "Insufficient fees for transferAndCall request should revert.");
        } else {
            vm.prank(user);
            vm.expectRevert();
            (bool success,) = address(compliantProxy).call(
                abi.encodeWithSignature("requestKycStatus(address,bool,bytes)", user, isAutomation, compliantCalldata)
            );
            require(!success, "Insufficient fees for requestKycStatus should revert.");
        }
    }

    /// @dev onlyCompliant
    function doSomething(uint256 addressSeed) public {
        address user = _createOrGetUser(addressSeed);
        require(user != proxyAdmin && user != compliantProxy, "Invalid address used.");

        if (g_requestedAddressToStatus[user]) {
            vm.prank(user);
            (bool success,) = address(compliantProxy).call(abi.encodeWithSignature("doSomething()"));
            require(success, "delegate call in handler to doSomething() failed");

            // update some ghost
            g_manualIncrement++;
        }
    }

    /// @dev onlyOwner
    function withdrawFees(
        uint256 addressSeed,
        bool isCompliant,
        bool isAutomation,
        bytes calldata compliantCalldata,
        bool isOnTokenTransfer
    ) public {
        if (g_compliantFeesInLink == 0) {
            sendRequest(addressSeed, isCompliant, isAutomation, compliantCalldata, isOnTokenTransfer);
        } else {
            /// @dev getCompliantFeesToWithdraw and add it to ghost tracker
            (, bytes memory retData) =
                address(compliantProxy).call(abi.encodeWithSignature("getCompliantFeesToWithdraw()"));
            uint256 fees = abi.decode(retData, (uint256));

            vm.prank(compliant.owner());
            (bool success,) = address(compliantProxy).call(abi.encodeWithSignature("withdrawFees()"));
            require(success, "delegate call in handler to withdrawFees() failed");

            g_totalFeesWithdrawn += fees;
            g_compliantFeesInLink = 0;
        }
    }

    /// @dev onlyProxy
    // @review readability/modularity can be improved here
    function externalImplementationCalls(
        uint256 divisor,
        uint256 addressSeed,
        bool isAutomation,
        bytes memory compliantCalldata
    ) public {
        /// @dev increment ghost
        g_directImplementationCalls++;

        /// @dev get revealer and requestedAddress
        addressSeed = bound(addressSeed, 1, type(uint256).max - 1);
        address user = _seedToAddress(addressSeed);

        /// @dev make direct call to one of external functions
        uint256 choice = divisor % 5;
        if (choice == 0) {
            directOnTokenTransfer(user, isAutomation, compliantCalldata);
        } else if (choice == 1) {
            directRequestKycStatus(user, isAutomation, compliantCalldata);
        } else if (choice == 2) {
            directDoSomething();
        } else if (choice == 3) {
            directWithdrawFees();
        } else if (choice == 4) {
            directInitialize(user);
        } else {
            revert("Invalid choice");
        }
    }

    function directOnTokenTransfer(address user, bool isAutomation, bytes memory compliantCalldata) public {
        uint256 amount;
        if (isAutomation) amount = compliant.getFeeWithAutomation();
        else amount = compliant.getFee();
        deal(link, user, amount);

        bytes memory data = abi.encode(user, isAutomation, compliantCalldata);

        vm.prank(user);
        try LinkTokenInterface(link).transferAndCall(address(compliant), amount, data) {
            g_directCallSuccesses++;
        } catch (bytes memory error) {
            _handleOnlyProxyError(error);
        }
    }

    function directRequestKycStatus(address user, bool isAutomation, bytes memory compliantCalldata) public {
        uint256 amount;
        if (isAutomation) amount = compliant.getFeeWithAutomation();
        else amount = compliant.getFee();
        deal(link, user, amount);

        vm.prank(user);
        try compliant.requestKycStatus(user, isAutomation, compliantCalldata) {
            g_directCallSuccesses++;
        } catch (bytes memory error) {
            _handleOnlyProxyError(error);
        }
    }

    function directDoSomething() public {
        try compliant.doSomething() {
            g_directCallSuccesses++;
        } catch (bytes memory error) {
            _handleOnlyProxyError(error);
        }
    }

    function directWithdrawFees() public {
        try compliant.withdrawFees() {
            g_directCallSuccesses++;
        } catch (bytes memory error) {
            _handleOnlyProxyError(error);
        }
    }

    function directInitialize(address initialOwner) public {
        try compliant.initialize(initialOwner) {
            g_directCallSuccesses++;
        } catch (bytes memory error) {
            _handleOnlyProxyError(error);
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
    function _performUpkeep(address requestedAddress, bool isCompliant) internal {
        bytes32 requestId = bytes32(uint256(uint160(requestedAddress)));
        bytes memory performData = abi.encode(requestId, requestedAddress, isCompliant);

        vm.prank(forwarder);
        (bool success,) = address(compliantProxy).call(abi.encodeWithSignature("performUpkeep(bytes)", performData));
        require(success, "delegate call in handler to performUpkeep() failed");

        _updatePerformUpkeepGhosts(requestedAddress, isCompliant);
    }

    function _handleOnlyProxyError(bytes memory error) internal {
        g_directCallReverts++;

        bytes4 selector;
        assembly {
            selector := mload(add(error, 32))
        }
        assertEq(selector, bytes4(keccak256("Compliant__OnlyProxy()")));
    }

    function _startRequest(uint256 addressSeed, bool isCompliant, bool isAutomation)
        internal
        returns (address, uint256)
    {
        /// @dev create a user
        address user = _seedToAddress(addressSeed);
        require(user != proxyAdmin && user != compliantProxy, "Invalid address used.");
        /// @dev set the Everest status for the request
        _setEverestStatus(user, isCompliant);
        /// @dev deal link to user
        uint256 amount = _dealLink(user, isAutomation);

        return (user, amount);
    }

    function _updateRequestGhosts(address user, bool isAutomation, bytes memory compliantCalldata) internal {
        /// @dev store compliantCalldata in ghost mapping
        if (isAutomation && compliantCalldata.length > 0) {
            g_requestedAddressToCalldata[user] = compliantCalldata;
        }

        /// @dev set request to pending
        if (isAutomation) {
            g_pendingRequests[user] = true;
        }

        /// @dev update totalFeesEarned ghost
        g_totalFeesEarned += compliant.getFee() - IEverestConsumer(everest).oraclePayment();

        /// @dev increment requests made
        g_requestsMade++;
    }

    function _updatePerformUpkeepGhosts(address user, bool isCompliant) internal {
        /// @dev increment
        if (isCompliant) g_automationIncrement++;

        g_pendingRequests[user] = false;
        g_fulfilledUsers[user] = true;
        g_requestsFulfilled++;
    }

    function _handleRequestLogs(address user) internal {
        bytes32 kycStatusRequested = keccak256("KYCStatusRequested(bytes32,address)");
        bytes32 everestFulfilled = keccak256("Fulfilled(bytes32,address,address,uint8,uint40)");
        bytes32 kycStatusRequestFulfilled = keccak256("KYCStatusRequestFulfilled(bytes32,address,bool)");
        bytes32 compliantCheckPassed = keccak256("CompliantCheckPassed()");

        Vm.Log[] memory logs = vm.getRecordedLogs();

        for (uint256 i = 0; i < logs.length; i++) {
            /// @dev handle KYCStatusRequested() event params and ghosts
            if (logs[i].topics[0] == kycStatusRequested) {
                bytes32 emittedRequestId = logs[i].topics[1];
                address emittedUser = address(uint160(uint256(logs[i].topics[2])));

                g_requestedEventRequestId[emittedUser] = emittedRequestId;
                g_requestedUsers[emittedUser] = true;
                g_requestedEventsEmitted++;
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

            /// @dev handle KYCStatusRequestFulfilled() event params and ghost
            if (logs[i].topics[0] == kycStatusRequestFulfilled) {
                bytes32 emittedRequestId = logs[i].topics[1];
                g_compliantFulfilledEventRequestId[user] = emittedRequestId;

                /// @dev if isCompliant is true, increment ghost value
                if ((logs[i].topics[3] != bytes32(0))) {
                    g_fulfilledRequestIsCompliant++;
                    g_compliantFulfilledEventIsCompliant[user] = true;
                }

                g_compliantFulfilledEventsEmitted++;
            }

            /// @dev handle CompliantCheckPassed() event
            if (logs[i].topics[0] == compliantCheckPassed) {
                g_automatedCompliantCheckPassed++;
            }
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
        MockEverestConsumer(address(compliant.getEverest())).setLatestFulfilledRequest(
            false, isCompliant, isCompliant, address(compliantProxy), user, uint40(block.timestamp)
        );

        g_requestedAddressToStatus[user] = isCompliant;
    }

    /// @dev deal link to revealer to pay for funds and return amount
    function _dealLink(address receiver, bool isAutomation) internal returns (uint256) {
        uint256 amount;
        if (isAutomation) amount = compliant.getFeeWithAutomation();
        else amount = compliant.getFee();

        deal(link, receiver, amount);

        return amount;
    }
}
