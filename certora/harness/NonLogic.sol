// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

contract NonLogic {
    /*//////////////////////////////////////////////////////////////
                             ERRORS
    //////////////////////////////////////////////////////////////*/
    error NonLogic__CustomError();

    /*//////////////////////////////////////////////////////////////
                           VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @dev intended to be havoced by certora prover or set in specification
    bool internal s_success;

    /// @notice simulates unsuccessful supportsInterface call
    function supportsInterface(bytes4 interfaceId) external returns (bool) {
        bool success = getSuccess();
        if (success) return false;
        else revert NonLogic__CustomError();
    }

    /*//////////////////////////////////////////////////////////////
                                 GETTER
    //////////////////////////////////////////////////////////////*/
    function getSuccess() public view returns (bool) {
        return s_success;
    }
}