// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BaseTest} from "../../BaseTest.t.sol";

contract InitializeTest is BaseTest {
    function test_compliant_initialize_revertsWhen_alreadyInitialized() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        (bool success,) = address(compliantProxy).call(abi.encodeWithSignature("initialize(address)", user));
    }
}
