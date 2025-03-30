// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {BaseTest} from "../../BaseTest.t.sol";
import {MockEverestConsumer} from "../../mocks/MockEverestConsumer.sol";

contract GetIsCompliantTest is BaseTest {
    function test_compliant_getIsCompliant() public {
        _setUserToCompliant(user);
        (, bytes memory retData) =
            address(compliantProxy).call(abi.encodeWithSignature("getIsCompliant(address)", user));
        bool isCompliant = abi.decode(retData, (bool));
        assertTrue(isCompliant);
    }

    function test_compliant_getIsCompliantLogic() public view {
        address nonLogic = address(compliantRouter);

        assertTrue(compliantRouter.getIsCompliantLogic(address(logic)));
        assertFalse(compliantRouter.getIsCompliantLogic(address(nonLogic)));
    }
}
