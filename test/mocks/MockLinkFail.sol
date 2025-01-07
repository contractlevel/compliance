// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {MockLinkToken} from "./MockLinkToken.sol";

contract MockLinkFail is MockLinkToken {
    function transferFrom(address, address, uint256) public override returns (bool) {
        return false; // Simulate a failure
    }
}
