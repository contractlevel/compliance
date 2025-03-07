// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BaseTest, Vm, CompliantRouter, console2} from "../../BaseTest.t.sol";
import {LogicWrapperRevert} from "../../wrappers/LogicWrapperRevert.sol";

contract PerformUpkeepTest is BaseTest {
    function test_compliant_performUpkeep_isCompliant() public {
        /// @dev set user to pending request
        _setUserPendingRequest(address(logic), defaultGasLimit);

        /// @dev make sure the incremented value hasnt been touched
        uint256 incrementBefore = logic.getIncrementedValue();
        uint256 mapIncrementBefore = logic.getUserToIncrement(user);
        assertEq(incrementBefore, 0);
        assertEq(mapIncrementBefore, 0);

        /// @dev create performData
        bytes32 requestId = keccak256(abi.encodePacked(everest, everest.getNonce()));
        bytes memory performData = abi.encode(requestId, user, address(logic), defaultGasLimit, true);

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
                emittedBool = abi.decode(logs[i].data, (bool));
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
        _setUserPendingRequest(address(logic), defaultGasLimit);

        /// @dev make sure the incremented value hasnt been touched
        uint256 incrementBefore = logic.getIncrementedValue();
        uint256 mapIncrementBefore = logic.getUserToIncrement(user);
        assertEq(incrementBefore, 0);
        assertEq(mapIncrementBefore, 0);

        /// @dev create performData
        bytes32 requestId = keccak256(abi.encodePacked(everest, everest.getNonce()));
        bytes memory performData = abi.encode(requestId, user, address(logic), defaultGasLimit, false); // false for not compliant

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
                emittedBool = abi.decode(logs[i].data, (bool));
            }
        }

        /// @dev assert correct event params
        assertEq(requestId, emittedRequestId);
        assertEq(user, emittedUser);
        assertEq(address(logic), emittedLogic);
        assertFalse(emittedBool);

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

    function test_compliant_performUpkeep_handles_logicRevert() public {
        /// @dev set pending request with logic implementation that will revert
        LogicWrapperRevert logicRevert = new LogicWrapperRevert(address(compliantProxy));
        _setUserPendingRequest(address(logicRevert), defaultGasLimit);

        /// @dev create performData
        bytes32 requestId = keccak256(abi.encodePacked(everest, everest.getNonce()));
        bytes memory performData = abi.encode(requestId, user, address(logicRevert), defaultGasLimit, true);

        /// @dev call performUpkeep
        vm.recordLogs();
        vm.prank(forwarder);
        (bool success,) = address(compliantProxy).call(abi.encodeWithSignature("performUpkeep(bytes)", performData));
        require(success, "delegate call to performUpkeep failed");

        /// @dev assert CompliantLogicExecutionFailed event emitted with correct params
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 fulfilledEventSignature = keccak256("CompliantLogicExecutionFailed(bytes32,address,address,bool,bytes)");
        bytes32 emittedRequestId;
        address emittedUser;
        address emittedLogic;
        bool emittedBool;
        bytes memory emittedErr;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == fulfilledEventSignature) {
                emittedRequestId = logs[i].topics[1];
                emittedUser = address(uint160(uint256(logs[i].topics[2])));
                emittedLogic = address(uint160(uint256(logs[i].topics[3])));
                (emittedBool, emittedErr) = abi.decode(logs[i].data, (bool, bytes));
            }
        }

        bytes4 expectedErrorSelector = bytes4(keccak256("LogicWrapperRevert__Error()"));

        assertEq(requestId, emittedRequestId);
        assertEq(user, emittedUser);
        assertEq(address(logicRevert), emittedLogic);
        assertTrue(emittedBool);
        assertEq(bytes4(emittedErr), expectedErrorSelector);

        /// @dev assert request is no longer pending
        (, bytes memory retData) =
            address(compliantProxy).call(abi.encodeWithSignature("getPendingRequest(bytes32)", requestId));
        CompliantRouter.PendingRequest memory request = abi.decode(retData, (CompliantRouter.PendingRequest));
        assertFalse(request.isPending);
    }

    function test_compliant_performUpkeep_minimumGasLimitRequired() public {
        // this value is (around) the minimum gasLimit required for performUpkeep to successfully callback the LogicWrapper
        uint64 gasLimit = 45500; // 56575 58842 44421 59421

        /// @dev set user to pending request
        _setUserPendingRequest(address(logic), gasLimit);

        /// @dev create performData
        bytes32 requestId = keccak256(abi.encodePacked(everest, everest.getNonce()));
        bytes memory performData = abi.encode(requestId, user, address(logic), gasLimit, true);

        /// @dev Measure gas before function call
        uint256 gasBefore = gasleft();

        /// @dev execute performUpkeep
        vm.prank(forwarder);
        (bool success,) = address(compliantProxy).call(abi.encodeWithSignature("performUpkeep(bytes)", performData));
        /// @dev Ensure the call was successful
        require(success, "delegate call to performUpkeep failed");

        /// @dev Measure gas after function call
        uint256 gasAfter = gasleft();
        /// @dev Calculate actual gas used
        uint256 gasUsed = gasBefore - gasAfter;
        /// @dev Log the gas used for debugging
        console2.log("Gas used for performUpkeep execution:", gasUsed);

        /// @dev assert compliant state change has happened
        uint256 incrementAfter = logic.getIncrementedValue();
        uint256 mapIncrementAfter = logic.getUserToIncrement(user);
        assertEq(incrementAfter, 1);
        assertEq(mapIncrementAfter, 1);
    }
}
