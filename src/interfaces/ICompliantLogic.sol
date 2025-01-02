// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface ICompliantLogic {
    function compliantLogic(address user, bytes calldata data) external;
}
