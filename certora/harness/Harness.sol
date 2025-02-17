// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {CompliantRouter} from "../../src/CompliantRouter.sol";
import {IEverestConsumer} from "lib/everest-chainlink-consumer/contracts/EverestConsumer.sol";
import {LogicWrapper} from "../../test/wrappers/LogicWrapper.sol";
import {LogicWrapperRevert} from "../..//test/wrappers/LogicWrapperRevert.sol";
import {ICompliantLogic} from "../../src/interfaces/ICompliantLogic.sol";

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
    function onTokenTransferData(address user, address logic, uint64 gasLimit) external returns (bytes memory) {
        return abi.encode(user, logic, gasLimit);
    }

    /// @dev create performData to pass to performUpkeep
    function performData(bytes32 requestId, address user, address logic, uint64 gasLimit, bool isCompliant) 
        external returns (bytes memory) 
    {
        return abi.encode(requestId, user, logic, gasLimit, isCompliant);
    }

    /// @dev wrapper for _getLatestPrice() internal
    function getLatestPrice() external returns (uint256) {
        return _getLatestPrice();
    }
}