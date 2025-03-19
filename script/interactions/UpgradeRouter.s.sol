// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {
    ITransparentUpgradeableProxy,
    ProxyAdmin
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract UpgradeRouter is Script {
    function run() external returns (address proxy, address router) {
        address proxyAdmin = vm.envAddress("PROXY_ADMIN_ETH_SEPOLIA");
        proxy = vm.envAddress("PROXY_ETH_SEPOLIA");
        router = vm.envAddress("ROUTER_ETH_SEPOLIA");

        vm.startBroadcast();

        /// @dev upgradeToAndCall - set CompliantRouter to new implementation and initialize msg.sender to owner
        bytes memory initializeData = abi.encodeWithSignature("initialize(address)", msg.sender);
        // bytes memory initializeData = "";
        ProxyAdmin(proxyAdmin).upgradeAndCall(ITransparentUpgradeableProxy(proxy), router, initializeData);

        vm.stopBroadcast();

        return (proxy, router);
    }
}
