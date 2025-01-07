// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BaseTest, Vm, CompliantRouter} from "../BaseTest.t.sol";

contract PerformUpkeepTest is BaseTest {
    function test_compliant_performUpkeep_isCompliant() public {
        /// @dev set user to pending request
        _setUserPendingRequest();

        /// @dev make sure the incremented value hasnt been touched
        uint256 incrementBefore = logic.getIncrementedValue();
        uint256 mapIncrementBefore = logic.getUserToIncrement(user);
        assertEq(incrementBefore, 0);
        assertEq(mapIncrementBefore, 0);

        /// @dev create performData
        bytes32 requestId = bytes32(uint256(uint160(user)));
        bytes memory performData = abi.encode(requestId, user, address(logic), true);

        /// @dev call performUpkeep
        vm.recordLogs();
        vm.prank(forwarder);
        (bool success,) = address(compliantProxy).call(abi.encodeWithSignature("performUpkeep(bytes)", performData));
        require(success, "delegate call to performUpkeep failed");

        /// @dev check logs to make sure expected events are emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 fulfilledEventSignature = keccak256("CompliantStatusFulfilled(bytes32,address,address,bool)");
        bytes32 emittedRequestId;
        address emittedUser;
        address emittedLogic;
        bool emittedBool;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == fulfilledEventSignature) {
                emittedRequestId = logs[i].topics[1];
                emittedUser = address(uint160(uint256(logs[i].topics[2])));
                emittedLogic = address(uint160(uint256(logs[i].topics[3])));
                emittedBool = (logs[i].topics[3] != bytes32(0));
            }
        }

        /// @dev assert correct event params
        assertEq(requestId, emittedRequestId);
        assertEq(user, emittedUser);
        assertEq(address(logic), emittedLogic);
        assertTrue(emittedBool);

        /// @dev assert compliant state change has happened
        uint256 incrementAfter = logic.getIncrementedValue();
        uint256 mapIncrementAfter = logic.getUserToIncrement(user);
        assertEq(incrementAfter, 1);
        assertEq(mapIncrementAfter, 1);

        /// @dev assert compliantCalldata for request is now empty
        (, bytes memory requestRetDataAfter) =
            address(compliantProxy).call(abi.encodeWithSignature("getPendingRequest(bytes32)", requestId));
        CompliantRouter.PendingRequest memory request =
            abi.decode(requestRetDataAfter, (CompliantRouter.PendingRequest));
        assertFalse(request.isPending);
    }

    function test_compliant_performUpkeep_isNonCompliant() public {
        /// @dev set user to pending request
        _setUserPendingRequest();

        /// @dev make sure the incremented value hasnt been touched
        uint256 incrementBefore = logic.getIncrementedValue();
        uint256 mapIncrementBefore = logic.getUserToIncrement(user);
        assertEq(incrementBefore, 0);
        assertEq(mapIncrementBefore, 0);

        /// @dev create performData
        bytes32 requestId = bytes32(uint256(uint160(user)));
        bytes memory performData = abi.encode(requestId, user, address(logic), false); // false for not compliant

        /// @dev call performUpkeep
        vm.recordLogs();
        vm.prank(forwarder);
        (bool success,) = address(compliantProxy).call(abi.encodeWithSignature("performUpkeep(bytes)", performData));
        require(success, "delegate call to performUpkeep failed");

        /// @dev check logs to make sure expected events are emitted
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 fulfilledEventSignature = keccak256("CompliantStatusFulfilled(bytes32,address,address,bool)");
        bytes32 emittedRequestId;
        address emittedUser;
        address emittedLogic;
        bool emittedBool;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == fulfilledEventSignature) {
                emittedRequestId = logs[i].topics[1];
                emittedUser = address(uint160(uint256(logs[i].topics[2])));
                emittedLogic = address(uint160(uint256(logs[i].topics[3])));
                emittedBool = (logs[i].topics[3] != bytes32(0));
            }
        }

        /// @dev assert correct event params
        assertEq(requestId, emittedRequestId);
        assertEq(user, emittedUser);
        assertEq(address(logic), emittedLogic);
        assertTrue(emittedBool);

        /// @dev assert compliant state change has happened
        uint256 incrementAfter = logic.getIncrementedValue();
        uint256 mapIncrementAfter = logic.getUserToIncrement(user);
        assertEq(incrementAfter, 0);
        assertEq(mapIncrementAfter, 0);

        /// @dev assert compliantCalldata for request is now empty
        (, bytes memory requestRetDataAfter) =
            address(compliantProxy).call(abi.encodeWithSignature("getPendingRequest(bytes32)", requestId));
        CompliantRouter.PendingRequest memory request =
            abi.decode(requestRetDataAfter, (CompliantRouter.PendingRequest));
        assertFalse(request.isPending);
    }

    function test_compliant_performUpkeep_revertsWhen_not_forwarder() public {
        vm.expectRevert(abi.encodeWithSignature("CompliantRouter__OnlyForwarder()"));
        (bool success,) = address(compliantProxy).call(abi.encodeWithSignature("performUpkeep(bytes)", ""));
    }

    function test_compliant_performUpkeep_revertsWhen_notProxy() public {
        vm.expectRevert(abi.encodeWithSignature("CompliantRouter__OnlyProxy()"));
        compliantRouter.performUpkeep("");
    }
}
