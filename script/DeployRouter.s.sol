// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {CompliantRouter} from "../src/CompliantRouter.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployRouter is Script {
    function run() external returns (CompliantRouter, HelperConfig) {
        HelperConfig config = new HelperConfig();
        (address everest, address link, address linkUsdFeed,,, address forwarder) = config.activeNetworkConfig();

        address proxy = vm.envAddress("PROXY_ETH_SEPOLIA");
        uint256 upkeepId = vm.envUint("CLA_UPKEEP_ID_ETH_SEPOLIA");

        vm.startBroadcast();

        CompliantRouter router = new CompliantRouter(everest, link, linkUsdFeed, forwarder, upkeepId, proxy);

        vm.stopBroadcast();
        return (router, config);
    }
}
