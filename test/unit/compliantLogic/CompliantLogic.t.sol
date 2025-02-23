// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {BaseTest, Vm} from "../../BaseTest.t.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ICompliantLogic} from "../../../src/interfaces/ICompliantLogic.sol";

contract CompliantLogicTest is BaseTest {
    function test_compliantLogic_executeLogic() public {
        uint256 incrementBefore = logic.getIncrementedValue();
        uint256 userIncrementBefore = logic.getUserToIncrement(user);

        assertEq(incrementBefore, 0);
        assertEq(userIncrementBefore, 0);

        vm.prank(logic.getCompliantRouter());
        logic.executeLogic(user);

        uint256 incrementAfter = logic.getIncrementedValue();
        uint256 userIncrementAfter = logic.getUserToIncrement(user);

        assertEq(incrementAfter, 1);
        assertEq(userIncrementAfter, 1);
    }

    function test_compliantLogic_executeLogic_revertsWhen_notCompliantRouter() public {
        vm.expectRevert(abi.encodeWithSignature("CompliantLogic__OnlyCompliantRouter()"));
        logic.executeLogic(user);
    }
}
