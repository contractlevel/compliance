// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.24;

// import {BaseTest, Vm, CompliantRouter} from "../BaseTest.t.sol";

// contract PerformUpkeepTest is BaseTest {
//     function test_compliant_performUpkeep_isCompliant() public {
//         /// @dev set user to pending request
//         address logic;
//         _setUserPendingRequest(logic); // there is no longer compliantCalldata, we pass it logic
//         // bytes memory compliantCalldata = abi.encode(1);
//         // _setUserPendingRequest(compliantCalldata);
//         // /// @dev make sure the compliantCalldata stored for the pending request actually has data
//         // (, bytes memory requestRetDataBefore) =
//         //     address(compliantProxy).call(abi.encodeWithSignature("getPendingRequest(address)", user));
//         // CompliantRouter.PendingRequest memory pendingRequest =
//         //     abi.decode(requestRetDataBefore, (CompliantRouter.PendingRequest));
//         // assertTrue(pendingRequest.compliantCalldata.length > 0);

//         /// @dev make sure the incremented value hasnt been touched
//         (, bytes memory incrementedRetDataBefore) =
//             address(compliantProxy).call(abi.encodeWithSignature("getAutomatedIncrement()"));
//         uint256 incrementedValueBefore = abi.decode(incrementedRetDataBefore, (uint256));
//         assertEq(incrementedValueBefore, 0);

//         /// @dev create performData
//         bytes32 requestId = bytes32(uint256(uint160(user)));
//         bytes memory performData = abi.encode(requestId, user, true);

//         /// @dev call performUpkeep
//         vm.recordLogs();
//         vm.prank(forwarder);
//         (bool success,) = address(compliantProxy).call(abi.encodeWithSignature("performUpkeep(bytes)", performData));
//         require(success, "delegate call to performUpkeep failed");

//         /// @dev check logs to make sure expected events are emitted
//         Vm.Log[] memory logs = vm.getRecordedLogs();
//         bytes32 fulfilledEventSignature = keccak256("KYCStatusRequestFulfilled(bytes32,address,bool)");
//         bytes32 emittedRequestId;
//         address emittedUser;
//         bool emittedBool;
//         bytes32 compliantEventSignature = keccak256("CompliantCheckPassed()");
//         bool compliantEventEmitted;

//         for (uint256 i = 0; i < logs.length; i++) {
//             if (logs[i].topics[0] == fulfilledEventSignature) {
//                 emittedRequestId = logs[i].topics[1];
//                 emittedUser = address(uint160(uint256(logs[i].topics[2])));
//                 emittedBool = (logs[i].topics[3] != bytes32(0));
//             }

//             if (logs[i].topics[0] == compliantEventSignature) {
//                 compliantEventEmitted = true;
//             }
//         }

//         /// @dev assert correct event params
//         assertEq(requestId, emittedRequestId);
//         assertEq(user, emittedUser);
//         assertTrue(emittedBool);
//         assertTrue(compliantEventEmitted);

//         /// @dev assert compliant state change has happened
//         (, bytes memory incrementedRetDataAfter) =
//             address(compliantProxy).call(abi.encodeWithSignature("getAutomatedIncrement()"));
//         uint256 incrementedValueAfter = abi.decode(incrementedRetDataAfter, (uint256));
//         assertEq(incrementedValueAfter, 1);

//         /// @dev assert compliantCalldata for request is now empty
//         (, bytes memory requestRetDataAfter) =
//             address(compliantProxy).call(abi.encodeWithSignature("getPendingRequest(address)", user));
//         CompliantRouter.PendingRequest memory request =
//             abi.decode(requestRetDataAfter, (CompliantRouter.PendingRequest));
//         assertFalse(request.isPending);
//         assertEq(request.compliantCalldata.length, 0);
//     }

//     function test_compliant_performUpkeep_isNonCompliant() public {
//         /// @dev make sure the incremented value hasnt been touched
//         (, bytes memory incrementedRetDataBefore) =
//             address(compliantProxy).call(abi.encodeWithSignature("getAutomatedIncrement()"));
//         uint256 incrementedValueBefore = abi.decode(incrementedRetDataBefore, (uint256));
//         assertEq(incrementedValueBefore, 0);

//         /// @dev create performData
//         bytes32 requestId = bytes32(uint256(uint160(user)));
//         bytes memory performData = abi.encode(requestId, user, false); // false for isCompliant

//         /// @dev call performUpkeep
//         vm.recordLogs();
//         vm.prank(forwarder);
//         (bool success,) = address(compliantProxy).call(abi.encodeWithSignature("performUpkeep(bytes)", performData));
//         require(success, "delegate call to performUpkeep failed");

//         /// @dev check logs to make sure expected events are emitted
//         Vm.Log[] memory logs = vm.getRecordedLogs();
//         bytes32 fulfilledEventSignature = keccak256("KYCStatusRequestFulfilled(bytes32,address,bool)");
//         bytes32 emittedRequestId;
//         address emittedUser;
//         bool emittedBool;
//         bytes32 compliantEventSignature = keccak256("CompliantCheckPassed()");
//         bool compliantEventEmitted;

//         for (uint256 i = 0; i < logs.length; i++) {
//             if (logs[i].topics[0] == fulfilledEventSignature) {
//                 emittedRequestId = logs[i].topics[1];
//                 emittedUser = address(uint160(uint256(logs[i].topics[2])));
//                 emittedBool = (logs[i].topics[3] != bytes32(0));
//             }

//             if (logs[i].topics[0] == compliantEventSignature) {
//                 compliantEventEmitted = true;
//             }
//         }

//         /// @dev assert correct event params
//         assertEq(requestId, emittedRequestId);
//         assertEq(user, emittedUser);
//         assertFalse(emittedBool);
//         assertFalse(compliantEventEmitted);

//         /// @dev assert compliant protected state change has not happened
//         (, bytes memory incrementedRetDataAfter) =
//             address(compliantProxy).call(abi.encodeWithSignature("getAutomatedIncrement()"));
//         uint256 incrementedValueAfter = abi.decode(incrementedRetDataAfter, (uint256));
//         assertEq(incrementedValueAfter, 0);

//         /// @dev assert no compliantCalldata stored
//         (, bytes memory requestRetDataAfter) =
//             address(compliantProxy).call(abi.encodeWithSignature("getPendingRequest(address)", user));
//         CompliantRouter.PendingRequest memory request =
//             abi.decode(requestRetDataAfter, (CompliantRouter.PendingRequest));
//         assertFalse(request.isPending);
//         assertEq(request.compliantCalldata.length, 0);
//     }

//     function test_compliant_performUpkeep_revertsWhen_not_forwarder() public {
//         vm.expectRevert(abi.encodeWithSignature("Compliant__OnlyForwarder()"));
//         (bool success,) = address(compliantProxy).call(abi.encodeWithSignature("performUpkeep(bytes)", ""));
//     }

//     function test_compliant_performUpkeep_revertsWhen_notProxy() public {
//         vm.expectRevert(abi.encodeWithSignature("Compliant__OnlyProxy()"));
//         compliantRouter.performUpkeep("");
//     }
// }
