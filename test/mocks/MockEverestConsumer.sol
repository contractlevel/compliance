// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {IEverestConsumer} from "@everest/contracts/interfaces/IEverestConsumer.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";

contract MockEverestConsumer {
    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    using SafeERC20 for LinkTokenInterface;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error EverestConsumer__RevealeeShouldNotBeZeroAddress();

    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/
    // struct Request {
    //     bool isFulfilled; // 1 byte - slot 0
    //     bool isCanceled; // 1 byte - slot 0
    //     bool isHumanAndUnique; // 1 byte - slot 0
    //     bool isKYCUser; // 1 byte - slot 0
    //     address revealer; // 20 bytes - slot 0
    //     address revealee; // 20 bytes - slot 1
    //     // `kycTimestamp` is zero if the status is not `KYCUser`,
    //     // otherwise it is an epoch timestamp that represents the KYC date
    //     uint40 kycTimestamp; // 5 bytes - slot 1
    //     // expiration = block.timestamp while `requestStatus` + 5 minutes.
    //     // If `isFulfilled` and `isCanceled` are false by this time -
    //     // the the owner of the request can cancel its
    //     // request using `cancelRequest` and return paid link tokens
    //     uint40 expiration; // 5 bytes - slot 1
    // }

    address internal immutable i_link;

    uint256 internal s_oraclePayment = 1e17;
    bytes32 internal s_latestSentRequestId;
    mapping(bytes32 => IEverestConsumer.Request) internal s_requests;
    mapping(address revealee => IEverestConsumer.Request) internal s_requestsByRevealee;

    uint256 internal s_nonce;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address link) {
        i_link = link;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event Fulfilled(
        bytes32 _requestId,
        address indexed _revealer,
        address indexed _revealee,
        IEverestConsumer.Status _status,
        uint40 _kycTimestamp
    );

    /*//////////////////////////////////////////////////////////////
                                EXTERNAL
    //////////////////////////////////////////////////////////////*/
    function requestStatus(address _revealee) external {
        if (_revealee == address(0)) {
            revert EverestConsumer__RevealeeShouldNotBeZeroAddress();
        }

        // bytes32 requestId = bytes32(uint256(uint160(_revealee)));
        s_nonce++; // Increment the nonce to ensure uniqueness
        bytes32 requestId = keccak256(abi.encodePacked(_revealee, s_nonce));

        s_requests[requestId] = s_requestsByRevealee[_revealee];
        s_latestSentRequestId = requestId;

        IEverestConsumer.Status status;
        uint40 kycTimestamp;
        if (s_requests[requestId].isKYCUser) {
            status = IEverestConsumer.Status.KYCUser;
            kycTimestamp = s_requests[requestId].kycTimestamp;
        } else if (s_requests[requestId].isHumanAndUnique) {
            status = IEverestConsumer.Status.HumanAndUnique;
            kycTimestamp = 0;
        } else {
            status = IEverestConsumer.Status.NotFound;
            kycTimestamp = 0;
        }

        LinkTokenInterface(i_link).transferFrom(msg.sender, address(this), s_oraclePayment);

        emit Fulfilled(requestId, msg.sender, _revealee, status, kycTimestamp);
    }

    /*//////////////////////////////////////////////////////////////
                                 SETTER
    //////////////////////////////////////////////////////////////*/
    function setLatestFulfilledRequest(
        bool isCanceled,
        bool isHumanAndUnique,
        bool isKYCUser,
        address revealer,
        address revealee,
        uint40 kycTimestamp
    ) external {
        IEverestConsumer.Request memory request;

        request.isCanceled = isCanceled;
        request.isHumanAndUnique = isHumanAndUnique;
        request.isKYCUser = isKYCUser;
        request.revealer = revealer;
        request.revealee = revealee;
        request.kycTimestamp = kycTimestamp;
        request.expiration = uint40(block.timestamp + 5 minutes);

        s_requestsByRevealee[revealee] = request;
    }

    function setOraclePayment(uint256 _oraclePayment) external {
        s_oraclePayment = _oraclePayment;
    }

    /*//////////////////////////////////////////////////////////////
                                 GETTER
    //////////////////////////////////////////////////////////////*/
    function getLatestFulfilledRequest(address _revealee) external view returns (IEverestConsumer.Request memory) {
        return s_requestsByRevealee[_revealee];
    }

    function getLatestSentRequestId() external view returns (bytes32) {
        return s_latestSentRequestId;
    }

    function oraclePayment() external view returns (uint256 price) {
        return s_oraclePayment;
    }

    function getNonce() external view returns (uint256) {
        return s_nonce;
    }

    /// @notice Empty test function to ignore file in coverage report
    function test_mockEverest() public {}
}
