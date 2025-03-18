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
        } else if (block.chainid == 421614) {
            activeNetworkConfig = getArbSepoliaConfig();
        } else if (block.chainid == 11155111) {
            activeNetworkConfig = getEthSepoliaConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 GETTER
    //////////////////////////////////////////////////////////////*/
    function getPolygonConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            everest: 0xC1AfF12173B38aE44feDF453Af7A57AFF3cFd3f0,
            link: 0x53E0bca35eC356BD5ddDFebbD1Fc0fD03FaBad39,
            linkUsdFeed: 0xd9FFdb71EbE7496cC440152d43986Aae0AB76665,
            registry: 0x08a8eea76D2395807Ce7D1FC942382515469cCA1,
            registrar: 0x0Bc5EDC7219D272d9dEDd919CE2b4726129AC02B,
            forwarder: address(0)
        });
    }

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

    function getEthSepoliaConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            everest: address(0), // deployed mock
            link: 0x779877a7b0d9e8603169ddbd7836e478b4624789,
            linkUsdFeed: 0xc59E3633BAAC79493d908e63626716e204A45EdF,
            registry: 0x86EFBD0b6736Bed994962f9797049422A3A8E8Ad,
            registrar: 0xb0E49c5D0d05cbc241d68c05BC5BA1d1B7B72976,
            forwarder: address(0)
        })
    }

    function getArbSepoliaConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            everest: address(0), // deployed mock
            link: 0xb1D4538B4571d411F07960EF2838Ce337FE1E80E,
            linkUsdFeed: 0x0FB99723Aee6f420beAD13e6bBB79b7E6F034298,
            registry: 0x8194399B3f11fcA2E8cCEfc4c9A658c61B8Bf412,
            registrar: 0x881918E24290084409DaA91979A30e6f0dB52eBe,
            forwarder: address(0)
        })
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
