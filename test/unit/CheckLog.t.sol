// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.24;

// import {BaseTest, LinkTokenInterface, CompliantRouter} from "../BaseTest.t.sol";
// import {ILogAutomation, Log} from "@chainlink/contracts/src/v0.8/automation/interfaces/ILogAutomation.sol";
// import {IEverestConsumer} from "@everest/contracts/interfaces/IEverestConsumer.sol";

// /// review this - refactor tests for modularity/readability
// /// consider having function signature/selector for externally accessible functions in a Constants.sol
// contract CheckLogTest is BaseTest {
//     /*//////////////////////////////////////////////////////////////
//                                  TESTS
//     //////////////////////////////////////////////////////////////*/
//     /// @notice this test should be commented out if the cannotExecute modifier is removed from checkLog
//     function test_compliant_checkLog_revertsWhen_called() public {
//         Log memory log = _createLog(true, address(compliantRouter));
//         vm.expectRevert(abi.encodeWithSignature("OnlySimulatedBackend()"));
//         compliantRouter.checkLog(log, "");
//     }

//     /// @notice this test will fail unless the cannotExecute modifier is removed from checkLog
//     function test_compliant_checkLog_revertsWhen_notProxy() public {
//         Log memory log = _createLog(true, address(compliantRouter));
//         vm.expectRevert(abi.encodeWithSignature("Compliant__OnlyProxy()"));
//         compliantRouter.checkLog(log, "");
//     }

//     /// @notice this test will fail unless the cannotExecute modifier is removed from checkLog
//     function test_compliant_checkLog_isCompliant_and_pending() public {
//         /// @dev set user to pending request
//         bytes memory emptyCallData = "";
//         _setUserPendingRequest(emptyCallData);

//         /// @dev check log
//         Log memory log = _createLog(true, address(compliantProxy));

//         (, bytes memory retData) = address(compliantProxy).call(
//             abi.encodeWithSignature(
//                 "checkLog((uint256,uint256,bytes32,uint256,bytes32,address,bytes32[],bytes),bytes)", log, ""
//             )
//         );
//         (bool upkeepNeeded, bytes memory performData) = abi.decode(retData, (bool, bytes));

//         /// @dev decode performData
//         (bytes32 encodedRequestId, address encodedUser, bool isCompliant) =
//             abi.decode(performData, (bytes32, address, bool));

//         bytes32 expectedRequestId = bytes32(uint256(uint160(user)));
//         assertEq(expectedRequestId, encodedRequestId);
//         assertEq(user, encodedUser);
//         assertTrue(isCompliant);
//         assertTrue(upkeepNeeded);
//     }

//     /// @notice this test will fail unless the cannotExecute modifier is removed from checkLog
//     function test_compliant_checkLog_isNonCompliant_and_pending() public {
//         /// @dev set user to pending request
//         bytes memory emptyCallData = "";
//         _setUserPendingRequest(emptyCallData);

//         /// @dev check log
//         Log memory log = _createLog(false, address(compliantProxy));
//         (, bytes memory retData) = address(compliantProxy).call(
//             abi.encodeWithSignature(
//                 "checkLog((uint256,uint256,bytes32,uint256,bytes32,address,bytes32[],bytes),bytes)", log, ""
//             )
//         );
//         (bool upkeepNeeded, bytes memory performData) = abi.decode(retData, (bool, bytes));

//         /// @dev decode performData
//         (bytes32 encodedRequestId, address encodedUser, bool isCompliant) =
//             abi.decode(performData, (bytes32, address, bool));

//         bytes32 expectedRequestId = bytes32(uint256(uint160(user)));
//         assertEq(expectedRequestId, encodedRequestId);
//         assertEq(user, encodedUser);
//         assertFalse(isCompliant);
//         assertTrue(upkeepNeeded);
//     }

//     /// @notice this test will fail unless the cannotExecute modifier is removed from checkLog
//     function test_compliant_checkLog_isCompliant_and_notPending() public {
//         /// @dev check log
//         Log memory log = _createLog(true, address(compliantProxy));
//         (, bytes memory retData) = address(compliantProxy).call(
//             abi.encodeWithSignature(
//                 "checkLog((uint256,uint256,bytes32,uint256,bytes32,address,bytes32[],bytes),bytes)", log, ""
//             )
//         );
//         (bool upkeepNeeded, bytes memory performData) = abi.decode(retData, (bool, bytes));

//         assertEq(performData, "");
//         assertFalse(upkeepNeeded);
//     }

//     /// @notice this test will fail unless the cannotExecute modifier is removed from checkLog
//     function test_compliant_checkLog_revertsWhen_request_notCurrentContract() public {
//         address revealer = makeAddr("revealer");

//         /// @dev check log
//         Log memory log = _createLog(true, revealer);
//         vm.expectRevert(abi.encodeWithSignature("Compliant__RequestNotMadeByThisContract()"));
//         (, bytes memory retData) = address(compliantProxy).call(
//             abi.encodeWithSignature(
//                 "checkLog((uint256,uint256,bytes32,uint256,bytes32,address,bytes32[],bytes),bytes)", log, ""
//             )
//         );
//     }

//     /*//////////////////////////////////////////////////////////////
//                                 UTILITY
//     //////////////////////////////////////////////////////////////*/
//     function _createLog(bool isCompliant, address revealer) internal view returns (Log memory) {
//         bytes32[] memory topics = new bytes32[](3);
//         bytes32 eventSignature = keccak256("Fulfilled(bytes32,address,address,uint8,uint40)");
//         bytes32 requestId = bytes32(uint256(uint160(user)));
//         bytes32 addressToBytes32 = bytes32(uint256(uint160(revealer)));
//         topics[0] = eventSignature;
//         topics[1] = requestId;
//         topics[2] = addressToBytes32;

//         IEverestConsumer.Status status;

//         if (isCompliant) status = IEverestConsumer.Status.KYCUser;
//         else status = IEverestConsumer.Status.NotFound;

//         bytes memory data = abi.encode(user, status, block.timestamp);

//         Log memory log = Log({
//             index: 0,
//             timestamp: block.timestamp,
//             txHash: bytes32(0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef),
//             blockNumber: block.number,
//             blockHash: bytes32(0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890),
//             source: address(everest),
//             topics: topics,
//             data: data
//         });

//         return log;
//     }
// }
