// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {CompliantLogic} from "../../src/CompliantLogic.sol";

contract LogicHarness is CompliantLogic {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error LogicWrapperRevert__Error();

    /*//////////////////////////////////////////////////////////////
                           VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @dev intended to be havoced by certora prover or set in specification
    bool internal s_success;
    /// @dev incremented when a successful compliantLogic call is executed
    uint256 internal s_incrementedValue;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address router) CompliantLogic(router) {}

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/
    /// @notice the havoced bool will determine if the call is a success, allowing us to verify both outcomes
    function _executeLogic(address user) internal override {
        bool success = getSuccess();
        if (success) _success(user);
        else _revert(user);
    }

    /// @dev simulated successful CompliantLogic.compliantLogic call with state change
    function _success(address user) internal {
        s_incrementedValue++;
    }

    /// @dev simulated unsuccessful Compliant.compliantLogic call with revert
    function _revert(address user) internal {
        revert LogicWrapperRevert__Error();
    }

    /*//////////////////////////////////////////////////////////////
                                 GETTER
    //////////////////////////////////////////////////////////////*/
    function getIncrementedValue() external view returns (uint256) {
        return s_incrementedValue;
    }

    function getSuccess() public view returns (bool) {
        return s_success;
    }
}