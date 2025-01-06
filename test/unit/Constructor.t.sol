// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {BaseTest} from "../BaseTest.t.sol";

contract ConstructorTest is BaseTest {
    function test_compliant_constructor() public view {
        assertEq(address(compliantRouter.getEverest()), address(everest));
        assertEq(address(compliantRouter.getLink()), link);
        assertEq(address(compliantRouter.getLinkUsdFeed()), linkUsdFeed);
        assertEq(address(compliantRouter.getForwarder()), address(forwarder));
        assertEq(compliantRouter.getUpkeepId(), upkeepId);
        assertEq(compliantRouter.getProxy(), address(compliantProxy));
    }
}
