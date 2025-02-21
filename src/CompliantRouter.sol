// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IEverestConsumer} from "@everest/contracts/interfaces/IEverestConsumer.sol";
import {LinkTokenInterface} from "@chainlink/contracts/src/v0.8/shared/interfaces/LinkTokenInterface.sol";
import {ILogAutomation, Log} from "@chainlink/contracts/src/v0.8/automation/interfaces/ILogAutomation.sol";
import {AutomationBase} from "@chainlink/contracts/src/v0.8/automation/AutomationBase.sol";
import {IAutomationRegistryConsumer} from
    "@chainlink/contracts/src/v0.8/automation/interfaces/IAutomationRegistryConsumer.sol";
import {IAutomationForwarder} from "@chainlink/contracts/src/v0.8/automation/interfaces/IAutomationForwarder.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IERC677Receiver} from "@chainlink/contracts/src/v0.8/shared/interfaces/IERC677Receiver.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {ICompliantLogic} from "./interfaces/ICompliantLogic.sol";
import {ICompliantRouter} from "./interfaces/ICompliantRouter.sol";

/// @notice This contract facilitates KYC status requests and routes automated responses to a CompliantLogic implementation.
contract CompliantRouter is ILogAutomation, AutomationBase, OwnableUpgradeable, IERC677Receiver, ICompliantRouter {
    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    using SafeERC20 for LinkTokenInterface;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error CompliantRouter__OnlyProxy();
    error CompliantRouter__OnlyLinkToken();
    error CompliantRouter__InsufficientLinkTransferAmount(uint256 requiredAmount);
    error CompliantRouter__OnlyForwarder();
    error CompliantRouter__RequestNotMadeByThisContract();
    error CompliantRouter__NotCompliantLogic(address invalidContract);
    error CompliantRouter__LinkTransferFailed();
    error CompliantRouter__InvalidUser();
    error CompliantRouter__RequestNotPending();
    error CompliantRouter__MaxGasLimitExceeded();
    error CompliantRouter__InvalidLog();

    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @notice this struct is used for requests that are pending Chainlink Automation
    /// @param user who's compliant status is being requested
    /// @param logic the CompliantLogic contract implemented and passed by the requester
    /// @param gasLimit maximum amount of gas to spend for CompliantLogic callback - default value is used if this is 0
    /// @param isPending if this is true and a Fulfilled event is emitted by Everest, Chainlink Automation will perform
    struct PendingRequest {
        address user;
        address logic;
        uint64 gasLimit;
        bool isPending;
    }

    /// @dev 18 token decimals
    uint256 internal constant WAD_PRECISION = 1e18;
    /// @dev $0.50 to 8 decimals because price feeds have 8 decimals
    /// @notice this value could be something different or even configurable
    /// this could be the max - review this
    uint256 internal constant COMPLIANT_FEE = 5e7; // 50_000_000
    /// @dev max gas limit for CompliantLogic callback
    // @review - check performGasLimit in Chainlink Automation and whether the max should change based on that
    uint64 internal constant MAX_GAS_LIMIT = 3_000_000;
    /// @dev default gas limit for CompliantLogic callback
    uint64 internal constant DEFAULT_GAS_LIMIT = 200_000;
    /// @dev min gas limit for CompliantLogic callback
    uint64 internal constant MIN_GAS_LIMIT = 50_000;

    /// @dev Everest Chainlink Consumer
    IEverestConsumer internal immutable i_everest;
    /// @dev LINK token contract
    LinkTokenInterface internal immutable i_link;
    /// @dev Chainlink PriceFeed for LINK/USD
    AggregatorV3Interface internal immutable i_linkUsdFeed;
    /// @dev Chainlink Automation forwarder
    IAutomationForwarder internal immutable i_forwarder;
    /// @dev Chainlink Automation upkeep/subscription ID
    uint256 internal immutable i_upkeepId;
    /// @dev Compliant Proxy that all calls should go through
    address internal immutable i_proxy;

    /// @dev tracks the accumulated fees for this contract in LINK
    uint256 internal s_compliantFeesInLink;
    /// @dev maps a requestId to a PendingRequest struct
    mapping(bytes32 requestId => PendingRequest) internal s_pendingRequests;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    /// @dev emitted when KYC status of an address is requested
    event CompliantStatusRequested(bytes32 indexed everestRequestId, address indexed user, address indexed logic);
    /// @dev emitted when KYC status of an address is fulfilled
    event CompliantStatusFulfilled(
        bytes32 indexed everestRequestId, address indexed user, address indexed logic, bool isCompliant
    );
    /// @dev emitted when callback to CompliantLogic fails
    event CompliantLogicExecutionFailed(
        bytes32 indexed requestId, address indexed user, address indexed logic, bool isCompliant, bytes err
    );

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    /// @dev prevent direct calls made to this contract
    modifier onlyProxy() {
        if (address(this) != i_proxy) revert CompliantRouter__OnlyProxy();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /// @param everest Everest Chainlink consumer
    /// @param link LINK token
    /// @param linkUsdFeed LINK/USD Chainlink PriceFeed
    /// @param forwarder Chainlink Automation forwarder
    /// @param upkeepId Chainlink Automation upkeep/subscription ID
    /// @param proxy Compliant Proxy address
    constructor(
        address everest,
        address link,
        address linkUsdFeed,
        address forwarder,
        uint256 upkeepId,
        address proxy
    ) {
        i_everest = IEverestConsumer(everest);
        i_link = LinkTokenInterface(link);
        i_linkUsdFeed = AggregatorV3Interface(linkUsdFeed);
        i_forwarder = IAutomationForwarder(forwarder);
        i_upkeepId = upkeepId;
        i_proxy = proxy;
    }

    /*//////////////////////////////////////////////////////////////
                                EXTERNAL
    //////////////////////////////////////////////////////////////*/
    /// @notice transferAndCall LINK to address(this) to skip executing 2 txs with approve and requestKycStatus
    /// @param amount fee to pay for the request - get it from getFee()
    /// @param data encoded data should contain the user address to request the kyc status of and the address of the
    /// CompliantLogic contract to call with fulfilled result
    function onTokenTransfer(
        address,
        /* sender */
        uint256 amount,
        bytes calldata data
    ) external onlyProxy {
        if (msg.sender != address(i_link)) revert CompliantRouter__OnlyLinkToken();

        (address user, address logic, uint64 gasLimit) = abi.decode(data, (address, address, uint64));

        _revertIfNotCompliantLogic(logic);
        _revertIfMaxGasLimitExceeded(gasLimit);

        uint256 fees = _handleFees(true); // true for isOnTokenTransfer
        if (amount < fees) {
            revert CompliantRouter__InsufficientLinkTransferAmount(fees);
        }

        _requestKycStatus(user, logic, gasLimit);
    }

    /// @notice anyone can call this function to request the KYC status of their address
    /// @notice msg.sender must approve address(this) on LINK token contract
    /// @param user address to request kyc status of
    /// @param logic CompliantLogic contract to call when request is fulfilled
    /// @param gasLimit maximum amount of gas to spend for CompliantLogic callback - default value is used if this is 0
    function requestKycStatus(address user, address logic, uint64 gasLimit) external onlyProxy returns (uint256) {
        _revertIfNotCompliantLogic(logic);
        _revertIfMaxGasLimitExceeded(gasLimit);

        uint256 fee = _handleFees(false); // false for isOnTokenTransfer
        _requestKycStatus(user, logic, gasLimit);
        return fee;
    }

    /// @dev continuously simulated by Chainlink offchain Automation nodes
    /// @param log ILogAutomation.Log
    /// @return upkeepNeeded evaluates to true if the Fulfilled log contains a pending request
    /// @return performData contains fulfilled pending requestId, user, logic and if user isCompliant
    /// @notice for some unit tests to run successfully `cannotExecute` modifier should be commented out
    function checkLog(Log calldata log, bytes memory)
        external
        view
        cannotExecute
        onlyProxy
        returns (bool upkeepNeeded, bytes memory performData)
    {
        bytes32 eventSignature = keccak256("Fulfilled(bytes32,address,address,uint8,uint40)");

        if (log.source == address(i_everest) && log.topics[0] == eventSignature) {
            bytes32 requestId = log.topics[1];

            /// @dev revert if request wasn't made by this contract
            address revealer = address(uint160(uint256(log.topics[2])));
            if (revealer != address(this)) {
                revert CompliantRouter__RequestNotMadeByThisContract();
            }

            (address user, IEverestConsumer.Status kycStatus,) =
                abi.decode(log.data, (address, IEverestConsumer.Status, uint40));

            //slither-disable-next-line uninitialized-local
            bool isCompliant;
            if (kycStatus == IEverestConsumer.Status.KYCUser) {
                isCompliant = true;
            }

            PendingRequest memory request = s_pendingRequests[requestId];

            /// @dev revert if request's logic contract does not implement ICompliantLogic interface
            /// @notice this check is a bit redundant because we already do it, but checkLog costs no gas so may as well
            // review maybe we want to remove this check. probably doesnt matter if we verified requests revert if not logic
            address logic = request.logic;
            _revertIfNotCompliantLogic(logic);

            /// @dev revert if the user emitted by the Everest.Fulfill log is not the same as the one stored in request
            /// @notice this check is a bit redundant too
            if (user != request.user) revert CompliantRouter__InvalidUser();

            /// @dev revert if request is not pending
            if (!request.isPending) revert CompliantRouter__RequestNotPending();

            /// @dev get the gas limit for logic callback
            //slither-disable-next-line uninitialized-local
            uint64 gasLimit;
            if (request.gasLimit == 0) gasLimit = DEFAULT_GAS_LIMIT;
            else gasLimit = request.gasLimit;

            if (request.isPending) {
                performData = abi.encode(requestId, user, logic, gasLimit, isCompliant);
                upkeepNeeded = true;
            }
        } else {
            /// @dev revert if the log is not a Fulfilled event from the EverestConsumer contract
            revert CompliantRouter__InvalidLog();
        }
    }

    /// @notice called by Chainlink Automation forwarder when the request is fulfilled
    /// @dev this function should contain the logic restricted for compliant only users
    /// @param performData encoded bytes contains bytes32 requestId, address user, address logic and bool isCompliant
    function performUpkeep(bytes calldata performData) external onlyProxy {
        if (msg.sender != address(i_forwarder)) {
            revert CompliantRouter__OnlyForwarder();
        }

        (bytes32 requestId, address user, address logic, uint64 gasLimit, bool isCompliant) =
            abi.decode(performData, (bytes32, address, address, uint64, bool));

        s_pendingRequests[requestId].isPending = false;

        emit CompliantStatusFulfilled(requestId, user, logic, isCompliant);

        bytes memory callData = abi.encodeWithSelector(ICompliantLogic.compliantLogic.selector, user, isCompliant);

        // Perform the low-level call with the gas limit
        (bool success, bytes memory err) = logic.call{gas: gasLimit}(callData);

        /// @dev if logic implementation reverts, complete tx with event indicating as such
        if (!success) {
            // Emit an event to log the failure
            emit CompliantLogicExecutionFailed(requestId, user, logic, isCompliant, err);
        }
    }

    /// @dev admin function for withdrawing protocol fees
    function withdrawFees() external onlyProxy onlyOwner {
        uint256 compliantFeesInLink = s_compliantFeesInLink;
        s_compliantFeesInLink = 0;

        // review - should event be emitted here?

        //slither-disable-next-line unchecked-transfer
        i_link.transfer(owner(), compliantFeesInLink);
    }

    /// @dev admin function for initializing owner when upgrading proxy to this implementation
    /// @notice lack of access control may currently be considered a "known issue"
    /// although if this is initialized in the same tx/script it is deployed, the issue would be null
    function initialize(address initialOwner) external onlyProxy initializer {
        __Ownable_init(initialOwner);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/
    /// @dev requests the kyc status of the user
    /// @param user who's status to request
    /// @param logic CompliantLogic contract to call when request is fulfilled
    /// @param gasLimit maximum amount of gas to spend for CompliantLogic callback - default value is used if this is 0
    function _requestKycStatus(address user, address logic, uint64 gasLimit) internal {
        i_everest.requestStatus(user);

        bytes32 requestId = i_everest.getLatestSentRequestId();

        _setPendingRequest(requestId, user, logic, gasLimit);

        emit CompliantStatusRequested(requestId, user, logic);

        // review do we want to return requestId? we'd return it in external requestKycStatus()
        // but what about onTokenTransfer?
    }

    /// @dev Chainlink Automation will only trigger for a true pending request
    /// @param requestId unique identifier for request returned from everest chainlink client
    /// @param user who's status to request
    /// @param logic CompliantLogic contract to call when request is fulfilled
    /// @param gasLimit maximum amount of gas to spend for CompliantLogic callback - default value is used if this is 0
    function _setPendingRequest(bytes32 requestId, address user, address logic, uint64 gasLimit) internal {
        // review - do we even need to write user to storage?
        s_pendingRequests[requestId].user = user;
        s_pendingRequests[requestId].logic = logic;
        s_pendingRequests[requestId].isPending = true;
        if (gasLimit >= MIN_GAS_LIMIT && gasLimit != DEFAULT_GAS_LIMIT) {
            s_pendingRequests[requestId].gasLimit = gasLimit;
        }
    }

    /// @dev calculates fees in LINK and handles approvals
    /// @param isOnTokenTransfer if the tx was initiated by erc677 onTokenTransfer, we don't need to transferFrom(msg.sender)
    function _handleFees(bool isOnTokenTransfer) internal returns (uint256) {
        uint256 compliantFeeInLink = _calculateCompliantFee();
        uint256 everestFeeInLink = _getEverestFee();
        uint96 automationFeeInLink = _getAutomationFee();

        s_compliantFeesInLink += compliantFeeInLink;

        uint256 totalFee = compliantFeeInLink + everestFeeInLink + automationFeeInLink;

        if (!isOnTokenTransfer) {
            if (!i_link.transferFrom(msg.sender, address(this), totalFee)) {
                revert CompliantRouter__LinkTransferFailed();
            }
        }

        IAutomationRegistryConsumer registry = i_forwarder.getRegistry();
        // review unused-return
        i_link.approve(address(registry), automationFeeInLink);
        registry.addFunds(i_upkeepId, automationFeeInLink);
        // review unused-return
        i_link.approve(address(i_everest), everestFeeInLink);

        return totalFee;
    }

    /// @dev reverts if logic does not implement expected interface
    function _revertIfNotCompliantLogic(address logic) internal view {
        if (!_isCompliantLogic(logic)) revert CompliantRouter__NotCompliantLogic(logic);
    }

    /// @dev reverts if the maximum gas limit for logic callback is exceeded
    function _revertIfMaxGasLimitExceeded(uint64 gasLimit) internal pure {
        if (gasLimit > MAX_GAS_LIMIT) revert CompliantRouter__MaxGasLimitExceeded();
    }

    /// @dev checks if the user is compliant
    function _isCompliant(address user) internal view returns (bool isCompliant) {
        IEverestConsumer.Request memory kycRequest = i_everest.getLatestFulfilledRequest(user);
        return kycRequest.isKYCUser;
    }

    /// @dev returns the latest LINK/USD price
    function _getLatestPrice() internal view returns (uint256) {
        //slither-disable-next-line unused-return
        (, int256 price,,,) = i_linkUsdFeed.latestRoundData();
        return uint256(price);
    }

    /// @dev calculates the fee for this contract
    function _calculateCompliantFee() internal view returns (uint256) {
        return (COMPLIANT_FEE * WAD_PRECISION) / _getLatestPrice();
    }

    /// @dev returns fee in LINK for an Everest request
    function _getEverestFee() internal view returns (uint256) {
        return i_everest.oraclePayment();
    }

    /// @dev returns fee in LINK for Chainlink Automation
    function _getAutomationFee() internal view returns (uint96) {
        IAutomationRegistryConsumer registry = i_forwarder.getRegistry();
        return registry.getMinBalance(i_upkeepId);
    }

    /// @notice Checks if a contract implements the ICompliantLogic interface
    /// @param logic The address of the target logic contract
    /// @return True if the contract supports the ICompliantLogic interface
    function _isCompliantLogic(address logic) internal view returns (bool) {
        try IERC165(logic).supportsInterface(type(ICompliantLogic).interfaceId) returns (bool result) {
            return result;
        } catch {
            return false;
        }
    }

    /*//////////////////////////////////////////////////////////////
                                 GETTER
    //////////////////////////////////////////////////////////////*/
    /// @param user address of user to query if they have completed KYC
    /// @return isCompliant True if the user has completed KYC
    function getIsCompliant(address user) external view returns (bool isCompliant) {
        return _isCompliant(user);
    }

    /// @notice returns the fee for a standard KYC request
    function getFee() external view returns (uint256) {
        uint256 compliantFeeInLink = _calculateCompliantFee();
        uint256 everestFeeInLink = _getEverestFee();
        uint256 automationFeeInLink = _getAutomationFee();

        return compliantFeeInLink + everestFeeInLink + automationFeeInLink;
    }

    /// @notice returns the amount that gets taken by the protocol without the everest and automation fees
    function getCompliantFee() external view returns (uint256) {
        return _calculateCompliantFee();
    }

    /// @notice returns the everest fee for a request
    function getEverestFee() external view returns (uint256) {
        return _getEverestFee();
    }

    /// @notice returns the automation fee for a request
    function getAutomationFee() external view returns (uint96) {
        return _getAutomationFee();
    }

    /// @notice returns the protocol fees available to withdraw by admin
    function getCompliantFeesToWithdraw() external view returns (uint256) {
        return s_compliantFeesInLink;
    }

    /// @notice returns PendingRequest struct mapped to requestId
    function getPendingRequest(bytes32 requestId) external view returns (PendingRequest memory) {
        return s_pendingRequests[requestId];
    }

    /// @notice returns Everest Consumer contract address
    function getEverest() external view returns (address) {
        return address(i_everest);
    }

    /// @notice returns LINK token contract address
    function getLink() external view returns (address) {
        return address(i_link);
    }

    /// @notice returns LINK/USD price feed contract
    function getLinkUsdFeed() external view returns (AggregatorV3Interface) {
        return i_linkUsdFeed;
    }

    /// @notice returns Chainlink Automation forwarder
    function getForwarder() external view returns (IAutomationForwarder) {
        return i_forwarder;
    }

    /// @notice returns Chainlink Automation upkeepID
    function getUpkeepId() external view returns (uint256) {
        return i_upkeepId;
    }

    /// @notice returns the proxy contract address to delegatecalls through
    function getProxy() external view returns (address) {
        return i_proxy;
    }

    /// @notice returns true if a contract address implements CompliantLogic interface
    function getIsCompliantLogic(address logic) external view returns (bool) {
        return _isCompliantLogic(logic);
    }

    /// @notice returns the default gas limit for CompliantLogic callback
    function getDefaultGasLimit() external pure returns (uint64) {
        return DEFAULT_GAS_LIMIT;
    }

    /// @notice returns the maximum gas limit for CompliantLogic callback
    function getMaxGasLimit() external pure returns (uint64) {
        return MAX_GAS_LIMIT;
    }

    /// @notice returns the minimum gas limit for CompliantLogic callback
    function getMinGasLimit() external pure returns (uint64) {
        return MIN_GAS_LIMIT;
    }
}
