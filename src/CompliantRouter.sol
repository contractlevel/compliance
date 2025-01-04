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

/// @notice A template contract for requesting and getting the KYC compliant status of an address.
contract CompliantRouter is ILogAutomation, AutomationBase, OwnableUpgradeable, IERC677Receiver {
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
    error CompliantRouter__NonCompliantUser(address nonCompliantUser);
    error CompliantRouter__PendingRequestExists(address pendingRequestedAddress);
    error CompliantRouter__OnlyForwarder();
    error CompliantRouter__RequestNotMadeByThisContract();
    error CompliantRouter__NotCompliantLogic(address invalidContract);
    error CompliantRouter__LinkTransferFailed();

    /*//////////////////////////////////////////////////////////////
                               VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @notice this struct is only used for requests that are pending Chainlink Automation
    /// @param logic the CompliantLogic contract implemented and passed by the requester
    /// @param isPending if this is true and a Fulfilled event is emitted by Everest, Chainlink Automation will perform
    struct PendingRequest {
        address logic;
        bool isPending;
    }

    /// @dev 18 token decimals
    uint256 internal constant WAD_PRECISION = 1e18;
    /// @dev $0.50 to 8 decimals because price feeds have 8 decimals
    /// @notice this value could be something different or even configurable
    /// this could be the max - review this
    uint256 internal constant COMPLIANT_FEE = 5e7; // 50_000_000

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
    /// @dev maps a user to a PendingRequest struct if the request requires Automation
    mapping(address user => PendingRequest) internal s_pendingRequests;

    /// @notice These two values are included for demo purposes
    /// @dev This can only be incremented by users who have completed KYC
    uint256 internal s_incrementedValue;
    /// @dev this can only be incremented by performUpkeep if a requested user is compliant
    uint256 internal s_automatedIncrement;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    /// @dev emitted when KYC status of an address is requested
    event CompliantStatusRequested(bytes32 indexed everestRequestId, address indexed user);
    /// @dev emitted when KYC status of an address is fulfilled
    event CompliantStatusFulfilled(bytes32 indexed everestRequestId, address indexed user, bool indexed isCompliant);

    /// @notice included for demo purposes
    event CompliantCheckPassed();

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
    /// @notice transferAndCall LINK to this address to skip executing 2 txs with approve and requestKycStatus
    /// @param amount fee to pay for the request - get it from getFee() or getFeeWithAutomation()
    // review this natspec
    /// @param data encoded data should contain the user address to request the kyc status of, a boolean
    /// indicating whether automation should be used to subsequently execute logic based on the immediate result,
    /// and arbitrary data to be passed to compliant restricted logic
    function onTokenTransfer(
        address,
        /* sender */
        uint256 amount,
        bytes calldata data
    ) external onlyProxy {
        if (msg.sender != address(i_link)) revert CompliantRouter__OnlyLinkToken();

        (address user, address logic) = abi.decode(data, (address, address));

        // review this
        bool isAutomated = logic != address(0);

        uint256 fees = _handleFees(isAutomated, true);
        if (amount < fees) {
            revert CompliantRouter__InsufficientLinkTransferAmount(fees);
        }

        _requestKycStatus(user, logic);
    }

    /// @notice anyone can call this function to request the KYC status of their address
    /// @notice msg.sender must approve address(this) on LINK token contract
    /// @param user address to request kyc status of
    /// @param isAutomated true if using automation to execute logic based on fulfilled request
    function requestKycStatus(address user, address logic) external onlyProxy returns (uint256) {
        // review this
        bool isAutomated = logic != address(0);

        uint256 fee = _handleFees(isAutomated, false);
        _requestKycStatus(user, logic);
        return fee;
    }

    // review this can be removed
    /// @notice example function that can only be called by a compliant user
    function doSomething() external onlyProxy {
        _revertIfNonCompliant(msg.sender);

        // compliant-restricted logic goes here
        s_incrementedValue++;
        emit CompliantCheckPassed();
    }

    /// @dev continuously simulated by Chainlink offchain Automation nodes
    /// @param log ILogAutomation.Log
    /// @return upkeepNeeded evaluates to true if the Fulfilled log contains a pending requested address
    /// @return performData contains fulfilled pending requestId, requestedAddress and if they are compliant
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

            (address requestedAddress, IEverestConsumer.Status kycStatus,) =
                abi.decode(log.data, (address, IEverestConsumer.Status, uint40));

            bool isCompliant;
            if (kycStatus == IEverestConsumer.Status.KYCUser) {
                isCompliant = true;
            }

            PendingRequest memory request = s_pendingRequests[requestedAddress];

            /// @dev revert if request's logic contract does not implement ICompliantLogic interface
            address logic = request.logic;
            if (!isCompliantLogic(logic)) revert CompliantRouter__NotCompliantLogic(logic);

            if (request.isPending) {
                performData = abi.encode(requestId, requestedAddress, logic, isCompliant);
                upkeepNeeded = true;
            }
        }
    }

    /// @notice called by Chainlink Automation forwarder when the request is fulfilled
    /// @dev this function should contain the logic restricted for compliant only users
    /// @param performData encoded bytes contains bytes32 requestId, address of requested user and bool isCompliant
    function performUpkeep(bytes calldata performData) external onlyProxy {
        if (msg.sender != address(i_forwarder)) {
            revert CompliantRouter__OnlyForwarder();
        }
        (bytes32 requestId, address user, address logic, bool isCompliant) =
            abi.decode(performData, (bytes32, address, address, bool));

        s_pendingRequests[user].isPending = false;

        // review event params, possibly replace requestId with logic
        emit CompliantStatusFulfilled(requestId, user, isCompliant);

        if (isCompliant) {
            _executeCompliantLogic(user, logic);

            s_automatedIncrement++;
            emit CompliantCheckPassed();
        }
    }

    /// @dev admin function for withdrawing protocol fees
    function withdrawFees() external onlyProxy onlyOwner {
        uint256 compliantFeesInLink = s_compliantFeesInLink;
        s_compliantFeesInLink = 0;

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
    function _requestKycStatus(address user, address logic) internal {
        // _setPendingRequest(user, logic);

        i_everest.requestStatus(user);

        // review do we really need this
        // yes we should be using it to map to pendingRequest for when different logics request the same user
        bytes32 requestId = i_everest.getLatestSentRequestId();

        _setPendingRequest(requestId, user, logic);

        emit CompliantStatusRequested(requestId, user, logic);
    }

    /// @dev Chainlink Automation will only trigger for a true pending request
    function _setPendingRequest(bytes32 requestId, address user, address logic) internal {
        // review do we need to revert if already isPending? probably not
        s_pendingRequests[requestId].user = user;
        s_pendingRequests[requestId].logic = logic;
        s_pendingRequests[requestId].isPending = true;
    }

    /// @dev calculates fees in LINK and handles approvals
    /// @param isOnTokenTransfer if the tx was initiated by erc677 onTokenTransfer, we don't need to transferFrom(msg.sender)
    function _handleFees(bool isOnTokenTransfer) internal returns (uint256) {
        uint256 compliantFeeInLink = _calculateCompliantFee();
        uint256 everestFeeInLink = _getEverestFee();
        uint256 automationFeeInLink = _getAutomationFee();

        s_compliantFeesInLink += compliantFeeInLink;

        uint256 totalFee = compliantFeeInLink + everestFeeInLink + automationFeeInLink;

        if (!isOnTokenTransfer) {
            if (!i_link.transferFrom(msg.sender, address(this), totalFee)) {
                revert CompliantRouter__LinkTransferFailed();
            }
        }

        i_link.approve(address(registry), automationFeeInLink);
        registry.addFunds(i_upkeepId, automationFeeInLink);
        i_link.approve(address(i_everest), everestFeeInLink);

        return totalFee;
    }

    /// @notice calls compliantLogic on a target contract that has implemented CompliantLogic
    /// @param user The user address
    /// @param logic The address of the CompliantLogic contract
    function _executeCompliantLogic(address user, address logic) internal virtual {
        ICompliantLogic(logic).compliantLogic(user);
    }

    /// @dev reverts if the user is not compliant
    function _revertIfNonCompliant(address user) internal view {
        if (!_isCompliant(user)) revert CompliantRouter__NonCompliantUser(user);
    }

    /// @dev checks if the user is compliant
    function _isCompliant(address user) internal view returns (bool isCompliant) {
        IEverestConsumer.Request memory kycRequest = i_everest.getLatestFulfilledRequest(user);
        return kycRequest.isKYCUser;
    }

    /// @dev returns the latest LINK/USD price
    function _getLatestPrice() internal view returns (uint256) {
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
    function _getAutomationFee() internal view returns (uint256) {
        IAutomationRegistryConsumer registry = i_forwarder.getRegistry();
        return uint256(registry.getMinBalance(i_upkeepId));
    }

    /// @notice Checks if a contract implements the ICompliantLogic interface
    /// @param target The address of the target contract
    /// @return True if the contract supports the ICompliantLogic interface
    function _isCompliantLogic(address target) internal view returns (bool) {
        try IERC165(target).supportsInterface(type(ICompliantLogic).interfaceId) returns (bool result) {
            return result;
        } catch {
            // If supportsInterface fails or reverts, the target does not implement ERC165
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
    function getFee() public view returns (uint256) {
        uint256 compliantFeeInLink = _calculateCompliantFee();
        uint256 everestFeeInLink = _getEverestFee();
        uint256 automationFeeInLink = _getAutomationFee();

        return compliantFeeInLink + everestFeeInLink + automationFeeInLink;
    }

    /// @notice returns the amount that gets taken by the protocol without the everest and automation fees
    function getCompliantFee() external view returns (uint256) {
        return _calculateCompliantFee();
    }

    /// @notice returns the protocol fees available to withdraw by admin
    function getCompliantFeesToWithdraw() external view returns (uint256) {
        return s_compliantFeesInLink;
    }

    function getEverest() external view returns (address) {
        return address(i_everest);
    }

    function getLink() external view returns (address) {
        return address(i_link);
    }

    function getLinkUsdFeed() external view returns (AggregatorV3Interface) {
        return i_linkUsdFeed;
    }

    function getForwarder() external view returns (IAutomationForwarder) {
        return i_forwarder;
    }

    function getUpkeepId() external view returns (uint256) {
        return i_upkeepId;
    }

    function getProxy() external view returns (address) {
        return i_proxy;
    }

    function getPendingRequest(address user) external view returns (PendingRequest memory) {
        return s_pendingRequests[user];
    }

    /// @notice getter for example value
    function getIncrementedValue() external view returns (uint256) {
        return s_incrementedValue;
    }

    /// @notice getter for example value
    function getAutomatedIncrement() external view returns (uint256) {
        return s_automatedIncrement;
    }
}
