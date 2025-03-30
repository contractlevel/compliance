// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface ICompliantRouter {
    function getFee() external returns (uint256);
    function requestKycStatus(address user, address logic) external returns (uint256);
}
