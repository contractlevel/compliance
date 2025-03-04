// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {console2, Vm} from "forge-std/Test.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {CompliantRouter} from "../src/CompliantRouter.sol";
import {CompliantProxy} from "../src/proxy/CompliantProxy.sol";
import {InitialImplementation} from "../src/proxy/InitialImplementation.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy,
    ProxyAdmin
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {IAutomationRegistryMaster} from
    "@chainlink/contracts/src/v0.8/automation/interfaces/v2_2/IAutomationRegistryMaster.sol";

/// @notice Crosschain Routers - Parent/Child Routers - will require different deploy scripts
/// as only the Parent will need to be registered with Automation and interact with Everest
contract DeployRouter is Script {
    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/
    address internal deployer = vm.envAddress("DEPLOYER_ADDRESS");
    address internal proxyDeployer; // replace this
    address internal multiSig;

    /*//////////////////////////////////////////////////////////////
                                  RUN
    //////////////////////////////////////////////////////////////*/
    function run() external {
        /// @dev fetch network config and constructor params
        HelperConfig helperConfig = new HelperConfig();
        (address everest, address link, address linkUsdFeed, address registry, address registrar,) =
            helperConfig.activeNetworkConfig();

        /// @dev deploy InitialImplementation
        InitialImplementation initialImplementation = new InitialImplementation();
        console2.log("InitialImplementation deployed at:", address(initialImplementation));

        /// @dev record logs to get proxyAdmin contract address
        address proxyAdmin;
        vm.recordLogs();

        /// @dev deploy CompliantProxy
        CompliantProxy compliantProxy = new CompliantProxy(address(initialImplementation), proxyDeployer);
        console2.log("CompliantProxy deployed at:", address(compliantProxy));

        /// @dev get proxyAdmin contract address from logs
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventSignature = keccak256("AdminChanged(address,address)");
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSignature) {
                (, proxyAdmin) = abi.decode(logs[i].data, (address, address));
            }
        }
        /// @notice proxyAdmin should be stored somewhere, perhaps a JSON file
        console2.log("proxyAdmin:", proxyAdmin);

        /// @dev register automation
        uint256 upkeepId = _registerAutomation(address(compliantProxy), everest);
        address forwarder = IAutomationRegistryMaster(registry).getForwarder(upkeepId);

        /// @dev deploy CompliantRouter
        CompliantRouter compliantRouter =
            new CompliantRouter(everest, link, linkUsdFeed, forwarder, upkeepId, address(compliantProxy));

        /// @dev upgradeToAndCall - set CompliantRouter to new implementation and initialize multiSig to owner
        /// @notice multiSig should come from network config and be unique to each network!
        bytes memory initializeData = abi.encodeWithSignature("initialize(address)", multiSig);
        vm.prank(proxyDeployer);
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(address(compliantProxy)), address(compliantRouter), initializeData
        );
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/
    function _registerAutomation() internal {}
}
