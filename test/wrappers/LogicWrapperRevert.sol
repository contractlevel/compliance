// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {CompliantLogic} from "../../src/CompliantLogic.sol";
import {console2} from "forge-std/Test.sol";

contract LogicWrapperRevert is CompliantLogic {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error LogicWrapperRevert__Error();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address compliantRouter) CompliantLogic(compliantRouter) {}

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/
    function _compliantLogic(address user) internal override {
        revert LogicWrapperRevert__Error();
    }
}
