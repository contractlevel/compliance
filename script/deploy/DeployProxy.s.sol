// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Vm} from "forge-std/Test.sol";
import {Script} from "forge-std/Script.sol";
import {CompliantProxy} from "../../src/proxy/CompliantProxy.sol";
import {InitialImplementation} from "../../src/proxy/InitialImplementation.sol";

contract DeployProxy is Script {
    function run() external returns (CompliantProxy, InitialImplementation, address proxyAdmin) {
        vm.startBroadcast();

        vm.recordLogs();

        InitialImplementation impl = new InitialImplementation();
        CompliantProxy proxy = new CompliantProxy(address(impl), msg.sender);

        proxyAdmin = _getProxyAdmin();

        vm.stopBroadcast();
        return (proxy, impl, proxyAdmin);
    }

    function _getProxyAdmin() internal returns (address proxyAdmin) {
        /// @dev get proxyAdmin contract address from logs
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventSignature = keccak256("AdminChanged(address,address)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSignature) {
                (, proxyAdmin) = abi.decode(logs[i].data, (address, address));
            }
        }
        return proxyAdmin;
    }
}
