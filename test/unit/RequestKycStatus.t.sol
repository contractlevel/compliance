// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BaseTest, Vm, LinkTokenInterface, CompliantRouter, console2} from "../BaseTest.t.sol";

/// review these tests - can be refactored further to improve modularity/readability
contract RequestKycStatusTest is BaseTest {
    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() public override {
        BaseTest.setUp();

        uint256 approvalAmount = compliantRouter.getFee();

        vm.prank(user);
        LinkTokenInterface(link).approve(address(compliantProxy), approvalAmount);
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/
    function test_compliant_requestKycStatus_success() public {
        uint256 linkBalanceBefore = LinkTokenInterface(link).balanceOf(user);

        vm.recordLogs();

        uint256 expectedFee = compliantRouter.getFee();
        /// @dev call requestKycStatus
        uint256 actualFee = _requestKycStatus(user, expectedFee, user, address(logic));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventSignature = keccak256("CompliantStatusRequested(bytes32,address,address)");
        bytes32 emittedRequestId;
        address emittedUser;
        address emittedLogic;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSignature) {
                emittedRequestId = logs[i].topics[1];
                emittedUser = address(uint160(uint256(logs[i].topics[2])));
                emittedLogic = address(uint160(uint256(logs[i].topics[3])));
            }
        }

        uint256 linkBalanceAfter = LinkTokenInterface(link).balanceOf(user);
        bytes32 expectedRequestId = bytes32(uint256(uint160(user)));

        assertEq(linkBalanceAfter + expectedFee, linkBalanceBefore);
        assertEq(emittedRequestId, expectedRequestId);
        assertEq(user, emittedUser);
        assertEq(address(logic), emittedLogic);
        assertEq(actualFee, expectedFee);
    }

    function test_compliant_requestKycStatus_revertsWhen_userPendingRequest() public {
        uint256 approvalAmount = compliantRouter.getFee() * 2;
        vm.startPrank(user);
        LinkTokenInterface(link).approve(address(compliantProxy), approvalAmount);

        (bool success,) = address(compliantProxy).call(
            abi.encodeWithSignature("requestKycStatus(address,address)", user, address(logic))
        );
        require(success, "delegate call to requestKycStatus failed");

        vm.expectRevert(abi.encodeWithSignature("CompliantRouter__PendingRequestExists(address)", user));
        (bool success2,) = address(compliantProxy).call(
            abi.encodeWithSignature("requestKycStatus(address,bool,bytes)", user, address(logic))
        );
        vm.stopPrank();
    }

    function test_compliant_requestKycStatus_revertsWhen_notProxy() public {
        uint256 approvalAmount = compliantRouter.getFee();
        vm.startPrank(user);
        LinkTokenInterface(link).approve(address(compliantRouter), approvalAmount);
        vm.expectRevert(abi.encodeWithSignature("CompliantRouter__OnlyProxy()"));
        compliantRouter.requestKycStatus(user, address(logic));
        vm.stopPrank();
    }

    function test_compliant_requestKycStatus_revertsWhen_insufficientFee() public {
        uint256 insufficientFee = compliantRouter.getFee() - 1;

        vm.startPrank(user);
        LinkTokenInterface(link).approve(address(compliantProxy), insufficientFee);

        vm.expectRevert(abi.encodeWithSignature("CompliantRouter__LinkTransferFailed()"));
        (bool success,) = address(compliantProxy).call(
            abi.encodeWithSignature("requestKycStatus(address,address)", user, address(logic))
        );
        vm.stopPrank();
    }

    function test_compliant_requestKycStatus_revertsWhen_logicIncompatible() public {
        uint256 approvalAmount = compliantRouter.getFee();
        address nonLogic = makeAddr("nonLogic");

        vm.startPrank(user);
        LinkTokenInterface(link).approve(address(compliantRouter), approvalAmount);
        vm.expectRevert(abi.encodeWithSignature("CompliantRouter__NotCompliantLogic(address)", nonLogic));
        (bool success,) =
            address(compliantProxy).call(abi.encodeWithSignature("requestKycStatus(address,address)", user, nonLogic));
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                UTILITY
    //////////////////////////////////////////////////////////////*/
    function _requestKycStatus(address caller, uint256 linkApprovalAmount, address requestedAddress, address logic)
        internal
        returns (uint256)
    {
        vm.prank(caller);
        LinkTokenInterface(link).approve(address(compliantProxy), linkApprovalAmount);
        vm.prank(caller);
        (, bytes memory retData) = address(compliantProxy).call(
            abi.encodeWithSignature("requestKycStatus(address,address)", requestedAddress, logic)
        );
        uint256 actualFee = abi.decode(retData, (uint256));

        return actualFee;
    }
}
