// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {CompliantLogic} from "../../src/CompliantLogic.sol";

contract LogicWrapper is CompliantLogic {
    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256 internal s_incrementedValue;
    mapping(address user => uint256 increment) internal s_userToIncrements;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address compliantRouter) CompliantLogic(compliantRouter) {}

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/
    function _compliantLogic(address user) internal override {
        s_incrementedValue++;
        s_userToIncrements[user]++;
    }

    /*//////////////////////////////////////////////////////////////
                                 GETTER
    //////////////////////////////////////////////////////////////*/
    function getIncrementedValue() external view returns (uint256) {
        return s_incrementedValue;
    }

    function getUserToIncrement(address user) external view returns (uint256) {
        return s_userToIncrements[user];
    }
}
