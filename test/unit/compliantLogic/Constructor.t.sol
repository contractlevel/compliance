// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {BaseTest} from "../../BaseTest.t.sol";

contract ConstructorTest is BaseTest {
    function test_compliantLogic_constructor() public view {
        assertEq(logic.getCompliantRouter(), address(compliantProxy));
    }
}
