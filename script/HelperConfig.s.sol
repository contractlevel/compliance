// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {Script} from "forge-std/Script.sol";
import {MockEverestConsumer} from "../test/mocks/MockEverestConsumer.sol";
import {MockLinkToken} from "../test/mocks/MockLinkToken.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {MockAutomationRegistry} from "../test/mocks/MockAutomationRegistry.sol";
import {MockForwarder} from "../test/mocks/MockForwarder.sol";

contract HelperConfig is Script {
    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint8 constant DECIMALS = 8;
    int256 constant INITIAL_ANSWER = 15 * 1e8; // $15/LINK

    /*//////////////////////////////////////////////////////////////
                             NETWORK CONFIG
    //////////////////////////////////////////////////////////////*/
    struct NetworkConfig {
        address everest;
        address link;
        address linkUsdFeed;
        address registry;
        address registrar;
        address forwarder;
    }

    NetworkConfig public activeNetworkConfig;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor() {
        if (block.chainid == 137) {
            activeNetworkConfig = getPolygonConfig();
        } else if (block.chainid == 1) {
            activeNetworkConfig = getEthMainnetConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 GETTER
    //////////////////////////////////////////////////////////////*/
    function getPolygonConfig() public pure returns (NetworkConfig memory) {}

    function getEthMainnetConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            everest: address(0), // deployed mock
            link: 0x514910771AF9Ca656af840dff83E8264EcF986CA,
            linkUsdFeed: 0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c,
            registry: 0x6593c7De001fC8542bB1703532EE1E5aA0D458fD,
            registrar: 0x6B0B234fB2f380309D47A7E9391E29E9a179395a,
            forwarder: address(0)
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        MockLinkToken mockLink = new MockLinkToken();
        MockEverestConsumer mockEverest = new MockEverestConsumer(address(mockLink));
        MockV3Aggregator mockPriceFeed = new MockV3Aggregator(DECIMALS, INITIAL_ANSWER);
        MockAutomationRegistry mockAutomation = new MockAutomationRegistry(address(mockLink));
        MockForwarder mockForwarder = new MockForwarder(address(mockAutomation));

        return NetworkConfig({
            everest: address(mockEverest),
            link: address(mockLink),
            linkUsdFeed: address(mockPriceFeed),
            registry: address(mockAutomation),
            registrar: address(0),
            forwarder: address(mockForwarder)
        });
    }
}
