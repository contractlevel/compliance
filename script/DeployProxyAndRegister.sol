// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Vm} from "forge-std/Test.sol";
import {Script} from "forge-std/Script.sol";
import {CompliantProxy} from "../src/proxy/CompliantProxy.sol";
import {InitialImplementation} from "../src/proxy/InitialImplementation.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {IAutomationRegistryMaster} from
    "@chainlink/contracts/src/v0.8/automation/interfaces/v2_2/IAutomationRegistryMaster.sol";
import {IAutomationRegistrar, RegistrationParams, LogTriggerConfig} from "../src/interfaces/IAutomationRegistrar.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";

/// @notice this script is registering custom logic automation for some reason - @review
contract DeployProxy is Script {
    /*//////////////////////////////////////////////////////////////
                                  RUN
    //////////////////////////////////////////////////////////////*/
    function run() external returns (CompliantProxy, InitialImplementation, HelperConfig, address, uint256, address) {
        HelperConfig config = new HelperConfig();
        (address everest, address link,, address registry, address registrar,) = config.activeNetworkConfig();

        vm.startBroadcast();

        /// @dev record logs to get proxyAdmin contract address
        vm.recordLogs();

        InitialImplementation impl = new InitialImplementation();
        CompliantProxy proxy = new CompliantProxy(address(impl), msg.sender);

        address proxyAdmin = _getProxyAdmin();

        /// @dev register automation
        uint256 upkeepId = _registerAutomation(address(proxy), everest, link, registrar);
        address forwarder = IAutomationRegistryMaster(registry).getForwarder(upkeepId);

        vm.stopBroadcast();
        return (proxy, impl, config, proxyAdmin, upkeepId, forwarder);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/
    /// @dev register Chainlink log trigger automation
    function _registerAutomation(address upkeepContract, address triggerContract, address link, address registrar)
        internal
        returns (uint256)
    {
        uint256 linkAmount = 5e18;

        LogTriggerConfig memory logTrigger = LogTriggerConfig({
            contractAddress: triggerContract,
            filterSelector: 2, // Filter only on topic 1 (_revealer)
            topic0: keccak256("Fulfilled(bytes32,address,address,uint8,uint40)"),
            topic1: bytes32(uint256(uint160(upkeepContract))),
            topic2: bytes32(0),
            topic3: bytes32(0)
        });

        RegistrationParams memory params = RegistrationParams({
            name: "",
            encryptedEmail: hex"",
            upkeepContract: upkeepContract,
            gasLimit: 5000000,
            adminAddress: msg.sender,
            triggerType: 1, // log trigger - WHY IS THIS REGISTERING WITH CUSTOM LOGIC????
            checkData: hex"",
            triggerConfig: abi.encode(logTrigger),
            offchainConfig: hex"",
            amount: uint96(linkAmount)
        });

        LinkTokenInterface(link).approve(registrar, linkAmount);
        return IAutomationRegistrar(registrar).registerUpkeep(params);
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
