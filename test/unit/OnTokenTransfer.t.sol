// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BaseTest, Vm, LinkTokenInterface, CompliantRouter, console2} from "../BaseTest.t.sol";
import {MockLinkToken} from "../mocks/MockLinkToken.sol";
import {LibZip} from "@solady/src/utils/LibZip.sol";

contract OnTokenTransferTest is BaseTest {
    function test_compliant_onTokenTransfer_noAutomation() public {
        uint256 amount = compliantRouter.getFee();
        /// @dev requesting the kyc status of user
        /// @dev false because we are not performing automation
        /// @dev "" for no compliantCalldata because we are not automating anything to pass it to
        bytes memory data = abi.encode(user, false, "");

        vm.recordLogs();

        vm.prank(user);
        LinkTokenInterface(link).transferAndCall(address(compliantProxy), amount, data);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventSignature = keccak256("KYCStatusRequested(bytes32,address)");
        bytes32 emittedRequestId;
        address emittedUser;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSignature) {
                emittedRequestId = logs[i].topics[1];
                emittedUser = address(uint160(uint256(logs[i].topics[2])));
            }
        }

        bytes32 expectedRequestId = bytes32(uint256(uint160(user)));

        assertEq(emittedRequestId, expectedRequestId);
        assertEq(user, emittedUser);
    }

    function test_compliant_onTokenTransfer_automation() public {
        uint256 amount = compliantRouter.getFee();
        bytes memory compliantCalldata = abi.encode(1);
        /// @dev requesting the kyc status of user
        /// @dev true because we are performing automation
        bytes memory data = abi.encode(user, true, compliantCalldata);

        vm.recordLogs();

        vm.prank(user);
        LinkTokenInterface(link).transferAndCall(address(compliantProxy), amount, data);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventSignature = keccak256("KYCStatusRequested(bytes32,address)");
        bytes32 emittedRequestId;
        address emittedUser;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSignature) {
                emittedRequestId = logs[i].topics[1];
                emittedUser = address(uint160(uint256(logs[i].topics[2])));
            }
        }

        bytes32 expectedRequestId = bytes32(uint256(uint160(user)));

        (, bytes memory retData) =
            address(compliantProxy).call(abi.encodeWithSignature("getPendingRequest(address)", user));

        CompliantRouter.PendingRequest memory pendingRequest = abi.decode(retData, (CompliantRouter.PendingRequest));
        bool isPending = pendingRequest.isPending;

        assertTrue(isPending);
        assertEq(emittedRequestId, expectedRequestId);
        assertEq(user, emittedUser);
    }

    function test_compliant_onTokenTransfer_revertsWhen_notLink() public {
        vm.startPrank(user);
        MockLinkToken erc677 = new MockLinkToken();
        erc677.initializeMockLinkToken();

        uint256 amount = compliantRouter.getFee();
        bytes memory data = abi.encode(user, false);

        vm.expectRevert(abi.encodeWithSignature("Compliant__OnlyLinkToken()"));
        erc677.transferAndCall(address(compliantProxy), amount, data);
        vm.stopPrank();
    }

    function test_compliant_onTokenTransfer_revertsWhen_insufficientAmount() public {
        vm.startPrank(user);
        uint256 fee = compliantRouter.getFee();
        uint256 amount = fee - 1;
        bytes memory data = abi.encode(user, false, "");

        vm.expectRevert(); // abi.encodeWithSignature("Compliant__InsufficientLinkTransferAmount(uint256,uint256)", amount, fee)
        LinkTokenInterface(link).transferAndCall(address(compliantProxy), amount, data);
        vm.stopPrank();
    }

    function test_compliant_onTokenTransfer_revertsWhen_notProxy() public {
        uint256 amount = compliantRouter.getFee();
        bytes memory compliantCalldata = abi.encode(1);
        /// @dev requesting the kyc status of user
        /// @dev true because we are performing automation
        bytes memory data = abi.encode(user, true, compliantCalldata);

        vm.prank(user);
        vm.expectRevert(); // abi.encodeWithSignature("Compliant__OnlyProxy()")
        LinkTokenInterface(link).transferAndCall(address(compliantRouter), amount, data);
    }
}
