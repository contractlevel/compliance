// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {BaseTest} from "../../BaseTest.t.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ICompliantLogic} from "../../../src/interfaces/ICompliantLogic.sol";

contract SupportsInterfaceTest is BaseTest {
    function test_compliantLogic_supportsInterface() public view {
        bool supportsLogic = logic.supportsInterface(type(ICompliantLogic).interfaceId);
        bool supportsErc165 = logic.supportsInterface(type(IERC165).interfaceId);

        assertEq(supportsLogic, true);
        assertEq(supportsErc165, true);
    }
}
