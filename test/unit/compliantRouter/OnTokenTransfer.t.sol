// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BaseTest, Vm, LinkTokenInterface, CompliantRouter, console2} from "../../BaseTest.t.sol";
import {MockLinkToken} from "../../mocks/MockLinkToken.sol";

contract OnTokenTransferTest is BaseTest {
    function test_compliant_onTokenTransfer_success() public {
        uint256 amount = compliantRouter.getFee();

        /// @dev requesting the kyc status of user and passing the logic address for callback
        bytes memory data = abi.encode(user, address(logic), defaultGasLimit);

        vm.recordLogs();

        vm.prank(user);
        LinkTokenInterface(link).transferAndCall(address(compliantProxy), amount, data);

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

        bytes32 expectedRequestId = keccak256(abi.encodePacked(everest, everest.getNonce() - 1));

        (, bytes memory retData) =
            address(compliantProxy).call(abi.encodeWithSignature("getPendingRequest(bytes32)", emittedRequestId));

        CompliantRouter.PendingRequest memory pendingRequest = abi.decode(retData, (CompliantRouter.PendingRequest));
        bool isPending = pendingRequest.isPending;

        assertTrue(isPending);
        assertEq(emittedRequestId, expectedRequestId);
        assertEq(user, emittedUser);
        assertEq(address(logic), emittedLogic);
        assertEq(address(logic), pendingRequest.logic);
        assertEq(user, pendingRequest.user);
    }

    function test_compliant_onTokenTransfer_revertsWhen_notLink() public {
        vm.startPrank(user);
        MockLinkToken erc677 = new MockLinkToken();
        erc677.initializeMockLinkToken();

        uint256 amount = compliantRouter.getFee();
        bytes memory data = abi.encode(user, false);

        vm.expectRevert(abi.encodeWithSignature("CompliantRouter__OnlyLinkToken()"));
        erc677.transferAndCall(address(compliantProxy), amount, data);
        vm.stopPrank();
    }

    function test_compliant_onTokenTransfer_revertsWhen_insufficientAmount() public {
        vm.startPrank(user);
        uint256 fee = compliantRouter.getFee();
        uint256 amount = fee - 1;
        bytes memory data = abi.encode(user, address(logic), defaultGasLimit);

        // abi.encodeWithSignature("CompliantRouter__InsufficientLinkTransferAmount(uint256,uint256)", amount, fee)
        vm.expectRevert();
        LinkTokenInterface(link).transferAndCall(address(compliantProxy), amount, data);
        vm.stopPrank();
    }

    function test_compliant_onTokenTransfer_revertsWhen_notProxy() public {
        uint256 amount = compliantRouter.getFee();
        bytes memory data = abi.encode(user, address(logic), defaultGasLimit);

        vm.prank(user);
        vm.expectRevert(); // abi.encodeWithSignature("CompliantRouter__OnlyProxy()")
        LinkTokenInterface(link).transferAndCall(address(compliantRouter), amount, data);
    }

    function test_compliant_onTokenTransfer_revertsWhen_logicIncompatible() public {
        uint256 amount = compliantRouter.getFee();
        address nonLogic = address(compliantRouter);
        bytes memory data = abi.encode(user, nonLogic, defaultGasLimit);

        vm.prank(user);
        vm.expectRevert(); // abi.encodeWithSignature("CompliantRouter__NotCompliantLogic(address)")
        LinkTokenInterface(link).transferAndCall(address(compliantRouter), amount, data);
    }

    function test_compliant_onTokenTransfer_revertsWhen_maxGasLimitExceeded() public {
        uint256 amount = compliantRouter.getFee();
        uint64 gasLimit = compliantRouter.getMaxGasLimit() + 1;
        bytes memory data = abi.encode(user, address(logic), gasLimit);

        vm.prank(user);
        vm.expectRevert(); // abi.encodeWithSignature("CompliantRouter__MaxGasLimitExceeded()")
        LinkTokenInterface(link).transferAndCall(address(compliantProxy), amount, data);
    }
}
