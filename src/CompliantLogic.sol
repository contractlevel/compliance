// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ICompliantLogic} from "./interfaces/ICompliantLogic.sol";

/// @notice Base contract for compliant smart contracts - inherit and implement _compliantLogic()
abstract contract CompliantLogic is ICompliantLogic {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error CompliantLogic__OnlyCompliantRouter();

    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @dev CompliantRouter contract that makes KYC status requests and routes automated execution to address(this)
    address internal immutable i_compliantRouter;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /// @param compliantRouter CompliantRouter contract address
    constructor(address compliantRouter) {
        i_compliantRouter = compliantRouter;
    }

    /*//////////////////////////////////////////////////////////////
                                EXTERNAL
    //////////////////////////////////////////////////////////////*/
    function compliantLogic(bytes calldata data) external {
        if (msg.sender != i_compliantRouter) revert CompliantLogic__OnlyCompliantRouter();
        _compliantLogic(data);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/
    /// @notice override this function in your implementation
    function _compliantLogic(bytes calldata data) internal virtual;
}
