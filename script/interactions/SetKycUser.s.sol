// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {MockEverestConsumer} from "../../test/mocks/MockEverestConsumer.sol";
import {HelperConfig} from "../HelperConfig.s.sol";

contract SetKycUser is Script {
    function run() external {
        HelperConfig config = new HelperConfig();
        (address everest,,,,,) = config.activeNetworkConfig();
        address proxy = vm.envAddress("PROXY_ETH_SEPOLIA");

        vm.startBroadcast();
        MockEverestConsumer(everest).setLatestFulfilledRequest(
            false, true, true, proxy, msg.sender, uint40(block.timestamp)
        );
        vm.stopBroadcast();
    }
}

/**
 *  bool isCanceled,
 *  bool isHumanAndUnique,
 *  bool isKYCUser,
 *  address revealer,
 *  address revealee,
 *  uint40 kycTimestamp
 */
