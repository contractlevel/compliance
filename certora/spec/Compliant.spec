// Verification of CompliantRouter

using MockEverestConsumer as everest;
using MockForwarder as forwarder;
using MockAutomationRegistry as registry;
using ERC677 as link;
using LogicHarness as logic;
using NonLogic as nonLogic;

/*//////////////////////////////////////////////////////////////
                            METHODS
//////////////////////////////////////////////////////////////*/
methods {
    function getProxy() external returns(address) envfree;
    function getCompliantFeesToWithdraw() external returns(uint256) envfree;
    function getPendingRequest(bytes32) external returns(CompliantRouter.PendingRequest) envfree;
    function getEverest() external returns(address) envfree;
    function getIsCompliant(address) external returns (bool) envfree;
    function getIsCompliantLogic(address) external returns (bool) envfree;
    function getLink() external returns (address) envfree;
    function getFee() external returns (uint256) envfree;
    function getCompliantFee() external returns (uint256) envfree;
    function getForwarder() external returns (address) envfree;
    function getUpkeepId() external returns (uint256) envfree;
    function owner() external returns (address) envfree;
    function getEverestFee() external returns (uint256) envfree;
    function getAutomationFee() external returns (uint96) envfree;
    function getLatestPrice() external returns (uint256) envfree;
    function getMinGasLimit() external returns (uint64) envfree;
    function getMaxGasLimit() external returns (uint64) envfree;
    function getDefaultGasLimit() external returns (uint64) envfree;

    // External contract functions
    function everest.oraclePayment() external returns (uint256) envfree;
    function forwarder.getRegistry() external returns (address) envfree;
    function registry.getMinBalance(uint256) external returns (uint96) envfree;
    function link.balanceOf(address) external returns (uint256) envfree;
    function link.allowance(address,address) external returns (uint256) envfree;
    function everest.getNonce() external returns (uint256) envfree;

    // Wildcard dispatcher summaries
    function _.compliantLogic(address,bool) external => DISPATCHER(true);
    function _.supportsInterface(bytes4 interfaceId) external => DISPATCHER(true);

    // Harness helper functions
    function onTokenTransferData(address,address,uint64) external returns (bytes) envfree;
    function performData(bytes32,address,address,uint64,bool) external returns (bytes) envfree;
    function logic.getIncrementedValue() external returns (uint256) envfree;
    function logic.getSuccess() external returns (bool) envfree;
    function requestId(address) external returns (bytes32) envfree;
    function createLog(bytes32,bool,address,address,address) external returns (CompliantRouter.Log);
}

/*//////////////////////////////////////////////////////////////
                          DEFINITIONS
//////////////////////////////////////////////////////////////*/
/// @notice external functions that change state
definition canChangeState(method f) returns bool = 
	f.selector == sig:onTokenTransfer(address,uint256,bytes).selector || 
	f.selector == sig:requestKycStatus(address,address,uint64).selector ||
    f.selector == sig:performUpkeep(bytes).selector ||
    f.selector == sig:withdrawFees().selector ||
    f.selector == sig:initialize(address).selector;

/// @notice external functions that can be called to make request
definition canRequestStatus(method f) returns bool = 
	f.selector == sig:onTokenTransfer(address,uint256,bytes).selector || 
	f.selector == sig:requestKycStatus(address,address,uint64).selector;

definition CompliantStatusRequestedEvent() returns bytes32 =
// keccak256(abi.encodePacked("CompliantStatusRequested(bytes32,address,address)"))
    to_bytes32(0x1297acbddb1a242c07b4024d683367f4a1a0c0d3ce6cfd9acf2812731794850a);

definition CompliantStatusFulfilledEvent() returns bytes32 =
// keccak256(abi.encodePacked("CompliantStatusFulfilled(bytes32,address,address,bool)"))
    to_bytes32(0x08d4934b589edfc28d3af23561c13b50e96ddf19f47def663ba217a9ff720694);

definition CompliantLogicExecutionFailedEvent() returns bytes32 =
// keccak256(abi.encodePacked("CompliantLogicExecutionFailed(bytes32,address,address,bool,bytes)"))
    to_bytes32(0xf26409c317494206f6feac40c1676f1481f66716e008e26a4b09511c63fb16bb);

definition NonCompliantUserEvent() returns bytes32 =
// keccak256(abi.encodePacked("NonCompliantUser(address)"))
    to_bytes32(0x03b17d62eebc94823993c88b2f49c9bbe3e292260b1dd80e079dd3d43129cbfc);

definition EverestFulfilledEvent() returns bytes32 =
// keccak256(abi.encodePacked("Fulfilled(bytes32,address,address,uint8,uint40)"))
// keccak256("Fulfilled(bytes32,address,address,uint8,uint40)")
    to_bytes32(0x6d3b3a10e0131f9c51ce77634a8b45197a7e81e3577f98cbe02df2752fe20024);

/// @notice 1e18
definition WAD_PRECISION() returns uint256 = 1000000000000000000;

/// @notice 5e7 (50c in PriceFeed decimals)
definition COMPLIANT_FEE_PRECISION() returns uint256 = 50000000;

/*//////////////////////////////////////////////////////////////
                             GHOSTS
//////////////////////////////////////////////////////////////*/
/// @notice track total fees earned
persistent ghost mathint g_totalFeesEarned {
    init_state axiom g_totalFeesEarned == 0;
}

/// @notice track total fees withdrawn
persistent ghost mathint g_totalFeesWithdrawn {
    init_state axiom g_totalFeesWithdrawn == 0;
}

/// @notice track the compliant restricted logic's incremented value 
ghost mathint g_incrementedValue {
    init_state axiom g_incrementedValue == 0;
}

/// @notice track CompliantStatusRequested() event emissions
ghost mathint g_compliantStatusRequestedEvents {
    init_state axiom g_compliantStatusRequestedEvents == 0;
}

/// @notice track CompliantStatusFulfilled() event emissions
ghost mathint g_compliantStatusFulfilledEvents {
    init_state axiom g_compliantStatusFulfilledEvents == 0;
}

/// @notice track CompliantLogicExecutionFailedEvent() event emissions
ghost mathint g_compliantLogicExecutionFailedEvents {
    init_state axiom g_compliantLogicExecutionFailedEvents == 0;
}

/// @notice track NonCompliantUser() event emissions
ghost mathint g_nonCompliantUserEvents {
    init_state axiom g_nonCompliantUserEvents == 0;
}

/// @notice track the gasLimit stored in a pending request
ghost mathint g_gasLimit {
    init_state axiom g_gasLimit == 0;
}

/*//////////////////////////////////////////////////////////////
                             HOOKS
//////////////////////////////////////////////////////////////*/
/// @notice update g_totalFeesEarned and g_totalFeesWithdrawn ghosts when s_compliantFeesInLink changes
hook Sstore s_compliantFeesInLink uint256 newValue (uint256 oldValue) {
    if (newValue >= oldValue) g_totalFeesEarned = g_totalFeesEarned + newValue - oldValue;
    else g_totalFeesWithdrawn = g_totalFeesWithdrawn + oldValue;
}

/// @notice update g_incrementedValue when s_incrementedValue increments
hook Sstore logic.s_incrementedValue uint256 newValue (uint256 oldValue) {
    if (newValue > oldValue) g_incrementedValue = g_incrementedValue + 1;
}

/// @notice update g_gasLimit when s_pendingRequests.gasLimit changes
hook Sstore s_pendingRequests[KEY bytes32 requestId].gasLimit uint64 newValue (uint64 oldValue) {
    if (newValue != oldValue) g_gasLimit = newValue;
}

/// @notice increment g_compliantStatusRequestedEvents when CompliantStatusRequested() emitted
/// @notice increment g_compliantStatusFulfilledEvents when CompliantStatusFulfilled() emitted
/// @notice increment g_compliantLogicExecutionFailedEvents when CompliantLogicExecutionFailed() emitted
hook LOG4(uint offset, uint length, bytes32 t0, bytes32 t1, bytes32 t2, bytes32 t3) {
    if (t0 == CompliantStatusRequestedEvent())
        g_compliantStatusRequestedEvents = g_compliantStatusRequestedEvents + 1;

    if (t0 == CompliantStatusFulfilledEvent()) 
        g_compliantStatusFulfilledEvents = g_compliantStatusFulfilledEvents + 1;

    if (t0 == CompliantLogicExecutionFailedEvent())
        g_compliantLogicExecutionFailedEvents = g_compliantLogicExecutionFailedEvents + 1;
}

/// @notice increment g_nonCompliantUserEvents when NonCompliantUser() emitted
hook LOG2(uint offset, uint length, bytes32 t0, bytes32 t1) {
    if (t0 == NonCompliantUserEvent())
        g_nonCompliantUserEvents = g_nonCompliantUserEvents + 1;
}

/*//////////////////////////////////////////////////////////////
                           INVARIANTS
//////////////////////////////////////////////////////////////*/
/// @notice total fees to withdraw must equal total fees earned minus total fees already withdrawn
invariant feesAccounting()
    to_mathint(getCompliantFeesToWithdraw()) == g_totalFeesEarned - g_totalFeesWithdrawn;

/*//////////////////////////////////////////////////////////////
                             RULES
//////////////////////////////////////////////////////////////*/
/// @notice direct calls to methods that change state should revert 
rule directCallsRevert(method f) filtered {f -> canChangeState(f)} {
    env e;
    calldataarg args;

    require currentContract != getProxy();

    f@withrevert(e, args);
    assert lastReverted;
}

/// @notice onTokenTransfer should revert if not called by LINK token
rule onTokenTransfer_revertsWhen_notLink() {
    env e;
    calldataarg args;

    require e.msg.sender != getLink();

    onTokenTransfer@withrevert(e, args);
    assert lastReverted;
}

/// @notice onTokenTransfer should revert if fee amount is insufficient
rule onTokenTransfer_revertsWhen_insufficientFee() {
    env e;
    address user;
    uint256 amount;
    uint64 gasLimit;
    bytes data = onTokenTransferData(user, logic, gasLimit);

    require amount < getFee();

    onTokenTransfer@withrevert(e, e.msg.sender, amount, data);
    assert lastReverted;
}

/// @notice checkLog is simulated offchain by CLA nodes and should revert
rule checkLogReverts() {
    env e;
    calldataarg args;
    
    require e.tx.origin != 0;
    require e.tx.origin != 0x1111111111111111111111111111111111111111;

    checkLog@withrevert(e, args);
    assert lastReverted;
}

/// @notice initialize should only be callable once and then it should always revert
rule initializeReverts() {
    env e;
    calldataarg args;

    initialize(e, args);
    initialize@withrevert(e, args);
    assert lastReverted;
}

/// @notice performUpkeep should revert if not called by the forwarder
rule performUpkeep_revertsWhen_notForwarder() {
    env e;
    calldataarg args;

    require e.msg.sender != getForwarder();

    performUpkeep@withrevert(e, args);
    assert lastReverted;
}

/// @notice fee calculation for requestKycStatus should be correct
rule requestKycStatus_feeCalculation() {
    env e;
    address user;
    address logicAddr;
    uint64 gasLimit;
    require link == getLink();
    require e.msg.sender != getEverest();
    require e.msg.sender != currentContract;
    require e.msg.sender != forwarder.getRegistry();

    uint256 balance_before = link.balanceOf(e.msg.sender);

    requestKycStatus(e, user, logicAddr, gasLimit);

    uint256 balance_after = link.balanceOf(e.msg.sender);

    assert balance_before == balance_after + getFee();
}

/// @notice fee calculation for onTokenTransfer should be correct
rule onTokenTransfer_feeCalculation() {
    env e;
    address user;
    address logicAddr;
    uint256 amount;
    uint64 gasLimit;
    bytes data;
    require data == onTokenTransferData(user, logicAddr, gasLimit);

    onTokenTransfer(e, e.msg.sender, amount, data);

    assert amount >= getFee();
}

/// @notice only owner should be able to call withdrawFees
rule withdrawFees_revertsWhen_notOwner() {
    env e;
    require currentContract == getProxy();
    require e.msg.sender != owner();

    withdrawFees@withrevert(e);
    assert lastReverted;
}

/// @notice LINK balance of the contract should decrease by the exact amount transferred to the owner in withdrawFees
rule withdrawFees_balanceIntegrity() {
    env e;
    require e.msg.sender != currentContract;
    require link == getLink();
    uint256 feesToWithdraw = getCompliantFeesToWithdraw();

    uint256 balance_before = link.balanceOf(currentContract);
    withdrawFees(e);
    uint256 balance_after = link.balanceOf(currentContract);

    assert balance_after == balance_before - feesToWithdraw;
}

/// @notice CompliantStatusRequested event is emitted for every request
rule requests_emit_events(method f) filtered {f -> canRequestStatus(f)} {
    env e;
    calldataarg args;

    require g_compliantStatusRequestedEvents == 0;

    f(e, args);

    assert g_compliantStatusRequestedEvents == 1;
}

/// @notice CompliantStatusFulfilled event is emitted for every fulfilled request
rule fulfilledRequest_emits_event() {
    env e;
    calldataarg args;

    require g_compliantStatusFulfilledEvents == 0;

    performUpkeep(e, args);

    assert g_compliantStatusFulfilledEvents == 1;
}

/// @notice requests must fund Everest with correct fee amount
rule requests_fundEverest(method f) filtered {f -> canRequestStatus(f)} {
    env e;
    calldataarg args;
    require link == getLink();
    require everest == getEverest();
    require e.msg.sender != everest;
    uint256 fee = everest.oraclePayment();

    uint256 balance_before = link.balanceOf(everest);

    require balance_before + fee <= max_uint;

    f(e, args);

    uint256 balance_after = link.balanceOf(everest);

    assert balance_after == balance_before + fee;
}

/// @notice requests must fund Automation registry with the correct amount
rule requests_fundRegistry(method f) filtered {f -> canRequestStatus(f)} {
    env e;
    calldataarg args;
    require link == getLink();
    require forwarder == getForwarder();
    require registry == forwarder.getRegistry();
    require e.msg.sender != forwarder.getRegistry();

    uint256 fee = registry.getMinBalance(getUpkeepId());

    uint256 balance_before = link.balanceOf(registry);

    require balance_before + fee <= max_uint;

    f(e, args);

    uint256 balance_after = link.balanceOf(registry);

    assert balance_after == balance_before + fee;
}

/// @notice sanity check to make sure the logicRevert implementation does revert as expected
rule logicReverts_check() {
    env e;
    require e.msg.sender == currentContract;
    address user;
    bool isCompliant = true;
    require logic.getSuccess() == false;

    logic.compliantLogic@withrevert(e, user, isCompliant);
    assert lastReverted;
}

/// @notice CompliantLogic implementations that revert shouldn't cause CompliantRouter to revert
rule logicReverts_handled() {
    env e;
    address user;
    bytes32 requestId;
    uint64 gasLimit;
    bool isCompliant = true;
    bytes performData = performData(requestId, user, logic, gasLimit, isCompliant);
    require gasLimit <= getMaxGasLimit();
    require e.msg.value == 0;
    require e.msg.sender == getForwarder();
    require currentContract == getProxy();
    require logic.getSuccess() == false;

    performUpkeep@withrevert(e, performData);
    assert !lastReverted;
}

/// @notice CompliantLogicExecutionFailed() event should be emitted when CompliantLogic reverts
rule logicReverts_emitsEvent() {
    env e;
    address user;
    bool isCompliant = true;
    uint64 gasLimit;
    bytes32 requestId;
    require gasLimit <= getMaxGasLimit();
    bytes performData = performData(requestId, user, logic, gasLimit, isCompliant);
    require e.msg.value == 0;
    require e.msg.sender == getForwarder();
    require currentContract == getProxy();
    require logic.getSuccess() == false;

    require g_compliantLogicExecutionFailedEvents == 0;

    performUpkeep@withrevert(e, performData);
    assert g_compliantLogicExecutionFailedEvents == 1;
}

/// @notice CompliantLogic must execute restricted logic (state change) on behalf of compliant user
rule compliantLogic_executes_for_compliantUser() {
    env e;
    address user;
    bool isCompliant = true;
    bytes32 requestId;
    uint64 gasLimit;
    require gasLimit <= getMaxGasLimit();
    bytes performData = performData(requestId, user, logic, gasLimit, isCompliant);

    require logic.getSuccess() == true;

    uint256 valueBefore = logic.getIncrementedValue();
    require valueBefore < max_uint;
    mathint ghostBefore = g_incrementedValue;

    performUpkeep(e, performData);

    uint256 valueAfter = logic.getIncrementedValue();
    mathint ghostAfter = g_incrementedValue;

    assert valueAfter == valueBefore + 1;
    assert ghostAfter == ghostBefore + 1;
}

/// @notice CompliantLogic must emit NonCompliantUser() event for non compliant users
rule compliantLogic_emitsEvent_for_nonCompliantUser() {
    env e;
    address user;
    bytes32 requestId;
    uint64 gasLimit;
    bool isCompliant = false;
    require gasLimit <= getMaxGasLimit();
    bytes performData = performData(requestId, user, logic, gasLimit, isCompliant);

    require logic.getSuccess() == true;
    require g_nonCompliantUserEvents == 0;

    performUpkeep(e, performData);

    assert g_nonCompliantUserEvents == 1;
}

/// @notice CompliantLogic restricted logic must not be executed on behalf of non compliant users
rule compliantLogic_does_not_execute_for_nonCompliantUser() {
    env e;
    address user;
    bytes32 requestId;
    bool isCompliant = false;
    uint64 gasLimit;
    require gasLimit <= getMaxGasLimit();
    bytes performData = performData(requestId, user, logic, gasLimit, isCompliant);

    require logic.getSuccess() == true;

    uint256 valueBefore = logic.getIncrementedValue();
    mathint ghostBefore = g_incrementedValue;

    performUpkeep(e, performData);

    uint256 valueAfter = logic.getIncrementedValue();
    mathint ghostAfter = g_incrementedValue;

    assert valueBefore == valueAfter;
    assert ghostBefore == ghostAfter;
}

/// @notice onTokenTransfer should revert if passed logic address does not implement expected interface
rule onTokenTransfer_revertsWhen_logicIncompatible() {
    env e;
    address user;
    uint256 amount;
    uint64 gasLimit;
    bytes data = onTokenTransferData(user, nonLogic, gasLimit);
    require amount >= getFee();
    require gasLimit < getMaxGasLimit();
    require e.msg.sender == getLink();
    require e.msg.value == 0;
    require user != 0;
    require currentContract == getProxy();
    require getCompliantFeesToWithdraw() < max_uint - getCompliantFee();
    require link.balanceOf(currentContract) >= amount;

    onTokenTransfer@withrevert(e, e.msg.sender, amount, data);
    assert lastReverted;
}

/// @notice onTokenTransfer should not revert under correct conditions
rule onTokenTransfer_noRevert() {
    env e;
    address user;
    uint256 amount;
    uint64 gasLimit;
    bytes data = onTokenTransferData(user, logic, gasLimit);
    require gasLimit < getMaxGasLimit();
    require amount >= getFee();
    require e.msg.sender == getLink();
    require e.msg.value == 0;
    require user != 0;
    require currentContract == getProxy();
    require getCompliantFeesToWithdraw() <= max_uint - getCompliantFee();
    require link.balanceOf(currentContract) >= amount;
    require everest.getNonce() < max_uint;

    onTokenTransfer@withrevert(e, e.msg.sender, amount, data);
    assert !lastReverted;
}

/// @notice requestKycStatus should not revert under correct conditions
rule requestKycStatus_noRevert() {
    env e;
    address user;
    uint64 gasLimit;
    require gasLimit <= getMaxGasLimit();
    require e.msg.value == 0;
    require e.msg.sender != registry;
    require e.msg.sender != everest;
    require e.msg.sender != 0;
    require user != 0;
    require currentContract == getProxy();
    require getCompliantFeesToWithdraw() <= max_uint - getCompliantFee();
    require link.balanceOf(currentContract) <= max_uint - getFee();
    require link.balanceOf(e.msg.sender) >= getFee();
    require link.allowance(e.msg.sender, currentContract) >= getFee();
    require everest.getNonce() < max_uint;

    requestKycStatus@withrevert(e, user, logic, gasLimit);
    assert !lastReverted;
}

/// @notice requestKycStatus should revert when passed logic address does not implement expected interface
rule requestKycStatus_revertsWhen_logicIncompatible() {
    env e;
    address user;
    uint64 gasLimit;
    require gasLimit <= getMaxGasLimit();
    require e.msg.value == 0;
    require e.msg.sender != registry;
    require e.msg.sender != everest;
    require e.msg.sender != 0;
    require user != 0;
    require currentContract == getProxy();
    require getCompliantFeesToWithdraw() <= max_uint - getCompliantFee();
    require link.balanceOf(currentContract) <= max_uint - getFee();
    require link.balanceOf(e.msg.sender) >= getFee();
    require link.allowance(e.msg.sender, currentContract) >= getFee();

    requestKycStatus@withrevert(e, user, nonLogic, gasLimit);
    assert lastReverted;
}

/// @notice calculation for protocol fee should be equal to 50c/LINK
rule compliantFeeCalculation {
    mathint fee = getCompliantFee();
    mathint expectedFee = (WAD_PRECISION() * COMPLIANT_FEE_PRECISION()) / getLatestPrice();
    assert fee == expectedFee;
}

/// @notice gas limit value should not be written to storage if it is default or below minimum value
rule requestKycStatus_gasLimit_noStorageWrite() {
    env e;
    address user;
    uint64 gasLimit;
    require gasLimit == getDefaultGasLimit() || gasLimit < getMinGasLimit();

    require g_gasLimit == 0;

    requestKycStatus(e, user, logic, gasLimit);

    assert g_gasLimit == 0;
}

/// @notice gas limit should write to storage if it is above minimum value and not default
rule requestKycStatus_gasLimit_storageWrite() {
    env e;
    address user;
    uint64 gasLimit;
    require gasLimit != getDefaultGasLimit();
    require gasLimit <= getMaxGasLimit();
    require gasLimit >= getMinGasLimit();
    
    require g_gasLimit == 0;

    bytes32 requestId = requestId(user);
    CompliantRouter.PendingRequest request = getPendingRequest(requestId);
    require request.gasLimit == 0;

    requestKycStatus(e, user, logic, gasLimit);

    assert g_gasLimit == gasLimit;
    assert g_gasLimit != 0;
}

/// @notice requestKycStatus should revert if max gas limit exceeded
rule requestKycStatus_revertsWhen_maxGasLimitExceeded() {
    env e;
    address user;
    uint64 gasLimit;
    require gasLimit > getMaxGasLimit();
    require e.msg.value == 0;
    require e.msg.sender != registry;
    require e.msg.sender != everest;
    require e.msg.sender != 0;
    require user != 0;
    require currentContract == getProxy();
    require getCompliantFeesToWithdraw() <= max_uint - getCompliantFee();
    require link.balanceOf(currentContract) <= max_uint - getFee();
    require link.balanceOf(e.msg.sender) >= getFee();
    require link.allowance(e.msg.sender, currentContract) >= getFee();

    requestKycStatus@withrevert(e, user, logic, gasLimit);
    assert lastReverted;
}

/// @notice gas limit value should not be written to storage if it is default or below minimum value
rule onTokenTransfer_gasLimit_noStorageWrite() {
    env e;
    address user;
    uint256 amount;
    uint64 gasLimit;
    require gasLimit == getDefaultGasLimit() || gasLimit < getMinGasLimit();
    bytes data = onTokenTransferData(user, logic, gasLimit);

    require g_gasLimit == 0;

    onTokenTransfer(e, e.msg.sender, amount, data);

    assert g_gasLimit == 0;
}

/// @notice gas limit should write to storage if it is above minimum value and not default
rule onTokenTransfer_gasLimit_storageWrite() {
    env e;
    address user;
    uint256 amount;
    uint64 gasLimit;
    require gasLimit != getDefaultGasLimit();
    require gasLimit < getMaxGasLimit();
    require gasLimit > getMinGasLimit();
    bytes data = onTokenTransferData(user, logic, gasLimit);
    
    bytes32 requestId = requestId(user);
    CompliantRouter.PendingRequest request = getPendingRequest(requestId);
    require request.gasLimit == 0;
    require g_gasLimit == 0;

    onTokenTransfer(e, e.msg.sender, amount, data);

    assert g_gasLimit == gasLimit;
    assert g_gasLimit != 0;
}

/// @notice onTokenTransfer should revert if max gas limit exceeded
rule onTokenTransfer_revertsWhen_maxGasLimitExceeded() {
    env e;
    address user;
    uint256 amount;
    uint64 gasLimit;
    require gasLimit > getMaxGasLimit();
    bytes data = onTokenTransferData(user, logic, gasLimit);
    require amount >= getFee();
    require e.msg.sender == getLink();
    require e.msg.value == 0;
    require user != 0;
    require currentContract == getProxy();
    require getCompliantFeesToWithdraw() < max_uint - getCompliantFee();
    require link.balanceOf(currentContract) >= amount;

    onTokenTransfer@withrevert(e, e.msg.sender, amount, data);
    assert lastReverted;
}

/// @notice checkLog should revert if not called via proxy
rule checkLog_revertsWhen_notProxy() {
    env e;
    calldataarg args;
    require currentContract != getProxy();
    require e.tx.origin == 0 || e.tx.origin == 0x1111111111111111111111111111111111111111;

    checkLog@withrevert(e, args);
    assert lastReverted;
}

/// @notice checkLog should revert if the log did not come from Everest
rule checkLog_revertsWhen_invalidLogSource() {
    env e;
    address user;
    bytes32 requestId = requestId(user);
    bool isCompliant;
    address invalidSource;
    bytes32 eventSignature = EverestFulfilledEvent();
    bytes data;

    require invalidSource != everest;
    require e.tx.origin == 0 || e.tx.origin == 0x1111111111111111111111111111111111111111;
    require currentContract == getProxy();

    CompliantRouter.Log log = createLog(e, requestId, isCompliant, currentContract, user, invalidSource, eventSignature);

    checkLog@withrevert(e, log, data);
    assert lastReverted;
}

/// @notice checkLog should revert if the log does not match the Fulfilled event
rule checkLog_revertsWhen_invalidLogEvent() {
    env e;
    address user;
    bytes32 requestId = requestId(user);
    bool isCompliant;
    bytes32 invalidEvent;
    bytes data;

    require invalidEvent != EverestFulfilledEvent();
    require e.tx.origin == 0 || e.tx.origin == 0x1111111111111111111111111111111111111111;
    require currentContract == getProxy();

    CompliantRouter.Log log = createLog(e, requestId, isCompliant, currentContract, user, everest, invalidEvent);

    checkLog@withrevert(e, log, data);
    assert lastReverted;
}

/// @notice checkLog should revert if the revealer address is not the Router/currentContract
rule checkLog_revertsWhen_invalidRevealer() {
    env e;
    address user;
    bytes32 requestId = requestId(user);
    bool isCompliant;
    bytes32 eventSignature = EverestFulfilledEvent();
    bytes data;
    address invalidRevealer;

    require e.tx.origin == 0 || e.tx.origin == 0x1111111111111111111111111111111111111111;
    require currentContract == getProxy();
    require invalidRevealer != currentContract;

    CompliantRouter.Log log = createLog(e, requestId, isCompliant, invalidRevealer, user, everest, eventSignature);

    checkLog@withrevert(e, log, data);
    assert lastReverted;
}