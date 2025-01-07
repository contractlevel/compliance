// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IAutomationRegistryConsumer} from
    "@chainlink/contracts/src/v0.8/automation/interfaces/IAutomationRegistryConsumer.sol";

contract MockForwarder {
    IAutomationRegistryConsumer internal s_registry;

    constructor(address registry) {
        s_registry = IAutomationRegistryConsumer(registry);
    }

    function getRegistry() external view returns (IAutomationRegistryConsumer) {
        return s_registry;
    }

    /// @notice Empty test function to ignore file in coverage report
    function test_mockForwarder() public {}
}
