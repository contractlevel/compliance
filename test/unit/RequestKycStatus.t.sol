// // SPDX-License-Identifier: MIT
// pragma solidity 0.8.24;

// import {BaseTest, Vm, LinkTokenInterface, CompliantRouter, console2} from "../BaseTest.t.sol";
// import {LibZip} from "@solady/src/utils/LibZip.sol";

// /// review these tests - can be refactored further to improve modularity/readability
// contract RequestKycStatusTest is BaseTest {
//     /*//////////////////////////////////////////////////////////////
//                                  SETUP
//     //////////////////////////////////////////////////////////////*/
//     function setUp() public override {
//         BaseTest.setUp();

//         uint256 approvalAmount = compliantRouter.getFee();

//         vm.prank(user);
//         LinkTokenInterface(link).approve(address(compliantProxy), approvalAmount);
//     }

//     /*//////////////////////////////////////////////////////////////
//                                  TESTS
//     //////////////////////////////////////////////////////////////*/
//     function test_compliant_requestKycStatus_success() public {
//         uint256 linkBalanceBefore = LinkTokenInterface(link).balanceOf(user);

//         vm.recordLogs();

//         uint256 expectedFee = compliantRouter.getFee();
//         /// @dev call requestKycStatus
//         uint256 actualFee = _requestKycStatus(user, expectedFee, user, false, "");

//         Vm.Log[] memory logs = vm.getRecordedLogs();
//         bytes32 eventSignature = keccak256("KYCStatusRequested(bytes32,address)");
//         bytes32 emittedRequestId;
//         address emittedUser;

//         for (uint256 i = 0; i < logs.length; i++) {
//             if (logs[i].topics[0] == eventSignature) {
//                 emittedRequestId = logs[i].topics[1];
//                 emittedUser = address(uint160(uint256(logs[i].topics[2])));
//             }
//         }

//         uint256 linkBalanceAfter = LinkTokenInterface(link).balanceOf(user);
//         bytes32 expectedRequestId = bytes32(uint256(uint160(user)));

//         assertEq(linkBalanceAfter + expectedFee, linkBalanceBefore);
//         assertEq(emittedRequestId, expectedRequestId);
//         assertEq(user, emittedUser);
//         assertEq(actualFee, expectedFee);
//     }

//     function test_compliant_requestKycStatus_automation() public {
//         uint256 linkBalanceBefore = LinkTokenInterface(link).balanceOf(user);

//         vm.recordLogs();

//         bytes memory compliantCalldata = abi.encode(1);

//         uint256 expectedFee = compliantRouter.getFeeWithAutomation();

//         /// @dev call requestKycStatus
//         uint256 actualFee = _requestKycStatus(user, expectedFee, user, true, compliantCalldata);

//         Vm.Log[] memory logs = vm.getRecordedLogs();
//         bytes32 eventSignature = keccak256("KYCStatusRequested(bytes32,address)");
//         bytes32 emittedRequestId;
//         address emittedUser;

//         for (uint256 i = 0; i < logs.length; i++) {
//             if (logs[i].topics[0] == eventSignature) {
//                 emittedRequestId = logs[i].topics[1];
//                 emittedUser = address(uint160(uint256(logs[i].topics[2])));
//             }
//         }

//         uint256 linkBalanceAfter = LinkTokenInterface(link).balanceOf(user);

//         bytes32 expectedRequestId = bytes32(uint256(uint160(user)));

//         (, bytes memory requestRetDataAfter) =
//             address(compliantProxy).call(abi.encodeWithSignature("getPendingRequest(address)", user));
//         CompliantRouter.PendingRequest memory pendingRequest =
//             abi.decode(requestRetDataAfter, (CompliantRouter.PendingRequest));
//         bool isPending = pendingRequest.isPending;
//         bytes memory storedCalldata = pendingRequest.compliantCalldata;

//         assertTrue(isPending);
//         /// @dev decompress storedCalldata
//         assertEq(LibZip.cdDecompress(storedCalldata), compliantCalldata);
//         assertEq(linkBalanceAfter + expectedFee, linkBalanceBefore);
//         assertEq(emittedRequestId, expectedRequestId);
//         assertEq(user, emittedUser);
//         assertEq(actualFee, expectedFee);
//     }

//     function test_compliant_requestKycStatus_revertsWhen_userPendingRequest() public {
//         uint256 approvalAmount = compliantRouter.getFeeWithAutomation() * 2;
//         vm.startPrank(user);
//         LinkTokenInterface(link).approve(address(compliantProxy), approvalAmount);

//         (bool success,) = address(compliantProxy).call(
//             abi.encodeWithSignature("requestKycStatus(address,bool,bytes)", user, true, "") // true for automation
//         );
//         require(success, "delegate call to requestKycStatus failed");

//         vm.expectRevert(abi.encodeWithSignature("Compliant__PendingRequestExists(address)", user));
//         (bool success2,) = address(compliantProxy).call(
//             abi.encodeWithSignature("requestKycStatus(address,bool,bytes)", user, true, "") // true for automation
//         );
//         vm.stopPrank();
//     }

//     function test_compliant_requestKycStatus_revertsWhen_notProxy() public {
//         uint256 approvalAmount = compliantRouter.getFee() * 2;
//         vm.startPrank(user);
//         LinkTokenInterface(link).approve(address(compliantRouter), approvalAmount);
//         vm.expectRevert(abi.encodeWithSignature("Compliant__OnlyProxy()"));
//         compliantRouter.requestKycStatus(user, true, ""); // true for automation
//     }

//     function test_compliant_requestKycStatus_revertsWhen_insufficientFee() public {
//         uint256 balance = LinkTokenInterface(link).balanceOf(user);
//         console2.log("balance:", balance); // 100_000000000000000000

//         vm.startPrank(user);
//         LinkTokenInterface(link).transfer(address(1), balance);
//         uint256 balanceAfter = LinkTokenInterface(link).balanceOf(user);
//         assertEq(balanceAfter, 0);

//         vm.expectRevert();
//         (bool success,) = address(compliantProxy).call(
//             abi.encodeWithSignature("requestKycStatus(address,bool,bytes)", user, true, "") // true for automation
//         );
//     }

//     /*//////////////////////////////////////////////////////////////
//                                 UTILITY
//     //////////////////////////////////////////////////////////////*/
//     function _requestKycStatus(
//         address caller,
//         uint256 linkApprovalAmount,
//         address requestedAddress,
//         bool isAutomation,
//         bytes memory compliantCalldata
//     ) internal returns (uint256) {
//         vm.prank(caller);
//         LinkTokenInterface(link).approve(address(compliantProxy), linkApprovalAmount);
//         vm.prank(caller);
//         (, bytes memory retData) = address(compliantProxy).call(
//             abi.encodeWithSignature(
//                 "requestKycStatus(address,bool,bytes)", requestedAddress, isAutomation, compliantCalldata
//             )
//         );
//         uint256 actualFee = abi.decode(retData, (uint256));

//         return actualFee;
//     }
// }
