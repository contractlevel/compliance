// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ICompliantLogic} from "./interfaces/ICompliantLogic.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @notice Base contract for compliant smart contracts - inherit and override _compliantLogic()
abstract contract CompliantLogic is ICompliantLogic, IERC165 {
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
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event NonCompliantUser(address indexed nonCompliantUser);

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
    /// @notice IERC165 supports an interfaceId
    /// @param interfaceId The interfaceId to check
    /// @return true if the interfaceId is supported
    /// @dev Should indicate whether the contract implements ICompliantLogic
    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(ICompliantLogic).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    /// @param user compliant status requestee
    /// @param isCompliant true if user has completed KYC with regulated entity
    function compliantLogic(address user, bool isCompliant) external {
        if (msg.sender != i_compliantRouter) revert CompliantLogic__OnlyCompliantRouter();
        if (isCompliant) _compliantLogic(user);
        else emit NonCompliantUser(user);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/
    /// @notice override this function in your implementation
    function _compliantLogic(address user) internal virtual;

    /*//////////////////////////////////////////////////////////////
                                 GETTER
    //////////////////////////////////////////////////////////////*/
    /// @notice returns the CompliantRouter contract address
    function getCompliantRouter() external view returns (address) {
        return i_compliantRouter;
    }
}
