// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {CompliantRouter, Log} from "../../src/CompliantRouter.sol";
import {IEverestConsumer} from "lib/everest-chainlink-consumer/contracts/EverestConsumer.sol";
import {LogicWrapper} from "../../test/wrappers/LogicWrapper.sol";
import {LogicWrapperRevert} from "../../test/wrappers/LogicWrapperRevert.sol";
import {ICompliantLogic} from "../../src/interfaces/ICompliantLogic.sol";
import {MockEverestConsumer} from "../../test/mocks/MockEverestConsumer.sol";

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

    /// @dev predict requestId
    function requestId(address user) external returns (bytes32) {
        uint256 nonce = MockEverestConsumer(address(i_everest)).getNonce() + 1;
        return keccak256(abi.encodePacked(user, nonce));
    }

    /// @dev extract function selector from logic calldata
    function extractSelector(uint argsOffset) external pure returns (bytes4) {
        bytes4 selector;
        assembly {
            selector := mload(argsOffset)
        }
        return selector;
    }
    
    /// @dev extract user address from logic calldata
    function extractAddress(uint argsOffset, uint argsLength) external pure returns (address) {
        require(argsLength >= 36, "Args length too short for selector and address");
        address user;
        assembly {
            let dataPtr := add(argsOffset, 4) // skip the 4-byte selector
            user := mload(dataPtr)            // load 32 bytes containing the address
        }
        return user;
    }

    /// @dev return selector for executeLogic
    function getExecuteLogicSelector() public pure returns (bytes4) {
        return ICompliantLogic.executeLogic.selector;
    }

    /// @dev create log for checkLog
    function createLog(
        bytes32 requestId,
        bool isCompliant,
        address revealer,
        address revealee,
        address source,
        bytes32 eventSignature
    )
        external view returns (Log memory)
    {
        bytes32[] memory topics = new bytes32[](3);
        bytes32 addressToBytes32 = bytes32(uint256(uint160(revealer)));
        topics[0] = eventSignature;
        topics[1] = requestId;
        topics[2] = addressToBytes32;

        IEverestConsumer.Status status;

        if (isCompliant) status = IEverestConsumer.Status.KYCUser;
        else status = IEverestConsumer.Status.NotFound;

        bytes memory data = abi.encode(revealee, status, block.timestamp);

        Log memory log = Log({
            index: 0,
            timestamp: block.timestamp,
            txHash: bytes32(0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef),
            blockNumber: block.number,
            blockHash: bytes32(0xabcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890),
            source: source,
            topics: topics,
            data: data
        });

        return log;
    }

    /// @dev convert bytes32 to uint256
    function bytes32ToUint256(bytes32 input) external pure returns (uint256) {
        return uint256(input);
    }

    /// @dev wrapper for _getLatestPrice() internal
    function getLatestPrice() external returns (uint256) {
        return _getLatestPrice();
    }
}