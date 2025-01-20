// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {CompliantRouter} from "../../src/CompliantRouter.sol";
import {IEverestConsumer} from "lib/everest-chainlink-consumer/contracts/EverestConsumer.sol";
import {LogicWrapper} from "../../test/wrappers/LogicWrapper.sol";
import {LogicWrapperRevert} from "../..//test/wrappers/LogicWrapperRevert.sol";

contract Harness is CompliantRouter {
    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address everest, address link, address linkUsdFeed, address forwarder, uint256 upkeepId, address proxy)
    CompliantRouter(everest, link, linkUsdFeed, forwarder, upkeepId, proxy)
    {}

    /*//////////////////////////////////////////////////////////////
                                UTILITY
    //////////////////////////////////////////////////////////////*/
    /// @dev create data to pass to onTokenTransfer
    function onTokenTransferData(address user, address logic) external returns (bytes memory) {
        return abi.encode(user, logic);
    }

    /// @dev create performData to pass to performUpkeep
    function performData(address user, address logic, bool isCompliant) external returns (bytes memory) {
        bytes32 requestId = bytes32(uint256(uint160(user)));
        return abi.encode(requestId, user, logic, isCompliant);
    }
}