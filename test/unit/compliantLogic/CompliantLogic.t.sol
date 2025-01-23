// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {BaseTest, Vm} from "../../BaseTest.t.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ICompliantLogic} from "../../../src/interfaces/ICompliantLogic.sol";

contract CompliantLogicTest is BaseTest {
    function test_compliantLogic_compliantLogic_nonCompliant() public {
        bool isCompliant = false;

        vm.recordLogs();

        vm.prank(logic.getCompliantRouter());
        logic.compliantLogic(user, isCompliant);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventSignature = keccak256("NonCompliantUser(address)");
        address emittedUser;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSignature) {
                emittedUser = address(uint160(uint256(logs[i].topics[1])));
            }
        }

        assertEq(user, emittedUser);
    }

    function test_compliantLogic_compliantLogic_isCompliant() public {
        bool isCompliant = true;

        vm.recordLogs();

        vm.prank(logic.getCompliantRouter());
        logic.compliantLogic(user, isCompliant);

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventSignature = keccak256("NonCompliantUser(address)");
        uint256 eventEmissions;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSignature) {
                eventEmissions++;
            }
        }

        assertEq(eventEmissions, 0);
    }

    function test_compliantLogic_compliantLogic_revertsWhen_notCompliantRouter() public {
        bool isCompliant;
        vm.expectRevert(abi.encodeWithSignature("CompliantLogic__OnlyCompliantRouter()"));
        logic.compliantLogic(user, isCompliant);
    }
}
