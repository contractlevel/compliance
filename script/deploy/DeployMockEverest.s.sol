// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {MockEverestConsumer} from "../../test/mocks/MockEverestConsumer.sol";
import {HelperConfig} from "../HelperConfig.s.sol";

contract DeployMockEverest is Script {
    function run() external returns (MockEverestConsumer, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (, address link,,,,) = config.activeNetworkConfig();

        vm.startBroadcast();
        MockEverestConsumer mockEverest = new MockEverestConsumer(link);
        vm.stopBroadcast();
        return (mockEverest, config);
    }
}
