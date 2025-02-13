// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BaseTest, Vm, LinkTokenInterface, CompliantRouter, console2} from "../../BaseTest.t.sol";
import {MockLinkFail} from "../../mocks/MockLinkFail.sol";
import {
    TransparentUpgradeableProxy,
    ITransparentUpgradeableProxy,
    ProxyAdmin
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/// review these tests - can be refactored further to improve modularity/readability
contract RequestKycStatusTest is BaseTest {
    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/
    function setUp() public override {
        BaseTest.setUp();

        uint256 approvalAmount = compliantRouter.getFee();

        vm.prank(user);
        LinkTokenInterface(link).approve(address(compliantProxy), approvalAmount);
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/
    function test_compliant_requestKycStatus_success() public {
        uint256 linkBalanceBefore = LinkTokenInterface(link).balanceOf(user);

        vm.recordLogs();

        uint256 expectedFee = compliantRouter.getFee();
        /// @dev call requestKycStatus
        uint256 actualFee = _requestKycStatus(user, expectedFee, user, address(logic));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 eventSignature = keccak256("CompliantStatusRequested(bytes32,address,address)");
        bytes32 emittedRequestId;
        address emittedUser;
        address emittedLogic;

        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == eventSignature) {
                emittedRequestId = logs[i].topics[1];
                emittedUser = address(uint160(uint256(logs[i].topics[2])));
                emittedLogic = address(uint160(uint256(logs[i].topics[3])));
            }
        }

        uint256 linkBalanceAfter = LinkTokenInterface(link).balanceOf(user);
        bytes32 expectedRequestId = bytes32(uint256(uint160(user)));

        assertEq(linkBalanceAfter + expectedFee, linkBalanceBefore);
        assertEq(emittedRequestId, expectedRequestId);
        assertEq(user, emittedUser);
        assertEq(address(logic), emittedLogic);
        assertEq(actualFee, expectedFee);
    }

    function test_compliant_requestKycStatus_revertsWhen_userPendingRequest() public {
        uint256 approvalAmount = compliantRouter.getFee() * 2;
        vm.startPrank(user);
        LinkTokenInterface(link).approve(address(compliantProxy), approvalAmount);

        (bool success,) = address(compliantProxy).call(
            abi.encodeWithSignature("requestKycStatus(address,address,uint64)", user, address(logic), defaultGasLimit)
        );
        require(success, "delegate call to requestKycStatus failed");

        vm.expectRevert(abi.encodeWithSignature("CompliantRouter__PendingRequestExists(address)", user));
        (bool success2,) = address(compliantProxy).call(
            abi.encodeWithSignature("requestKycStatus(address,bool,bytes)", user, address(logic))
        );
        vm.stopPrank();
    }

    function test_compliant_requestKycStatus_revertsWhen_notProxy() public {
        uint256 approvalAmount = compliantRouter.getFee();
        vm.startPrank(user);
        LinkTokenInterface(link).approve(address(compliantRouter), approvalAmount);
        vm.expectRevert(abi.encodeWithSignature("CompliantRouter__OnlyProxy()"));
        compliantRouter.requestKycStatus(user, address(logic), 0); // 0 for DEFAULT_GAS_LIMIT
        vm.stopPrank();
    }

    function test_compliant_requestKycStatus_revertsWhen_logicIncompatible() public {
        uint256 approvalAmount = compliantRouter.getFee();
        address nonLogic = address(compliantRouter);

        vm.startPrank(user);
        LinkTokenInterface(link).approve(address(compliantRouter), approvalAmount);
        vm.expectRevert(abi.encodeWithSignature("CompliantRouter__NotCompliantLogic(address)", nonLogic));
        (bool success,) = address(compliantProxy).call(
            abi.encodeWithSignature("requestKycStatus(address,address,uint64)", user, nonLogic, defaultGasLimit)
        );
        vm.stopPrank();
    }

    function test_compliant_requestKycStatus_revertsWhen_insufficientFee() public {
        uint256 insufficientFee = compliantRouter.getFee() - 1;

        vm.startPrank(user);
        LinkTokenInterface(link).approve(address(compliantProxy), insufficientFee);

        vm.expectRevert(abi.encodeWithSignature("CompliantRouter__LinkTransferFailed()"));
        (bool success,) = address(compliantProxy).call(
            abi.encodeWithSignature("requestKycStatus(address,address,uint64)", user, address(logic), defaultGasLimit)
        );
        vm.stopPrank();
    }

    function test_compliant_requestKycStatus_revertsWhen_linkFails() public {
        vm.prank(user);
        MockLinkFail linkFail = new MockLinkFail();

        /// @dev deploy infrastructure again with failing LINK token
        vm.prank(deployer);
        CompliantRouter compliantRouterLinkFail = new CompliantRouter(
            address(everest), address(linkFail), linkUsdFeed, forwarder, upkeepId, address(compliantProxy)
        );

        /// @dev upgradeToAndCall - set CompliantRouter to new implementation and initialize deployer to owner
        vm.prank(ProxyAdmin(proxyAdmin).owner());
        ProxyAdmin(proxyAdmin).upgradeAndCall(
            ITransparentUpgradeableProxy(address(compliantProxy)), address(compliantRouterLinkFail), ""
        );

        /// @dev approve LINK spending and assert revert for executing valid request with failing token
        vm.startPrank(user);
        LinkTokenInterface(link).approve(address(compliantProxy), compliantRouter.getFee());
        vm.expectRevert(abi.encodeWithSignature("CompliantRouter__LinkTransferFailed()"));
        (bool success,) = address(compliantProxy).call(
            abi.encodeWithSignature("requestKycStatus(address,address,uint64)", user, address(logic), defaultGasLimit)
        );
        vm.stopPrank();
    }

    function test_compliant_requestKycStatus_revertsWhen_maxGasLimitExceeded() public {
        uint64 gasLimit = compliantRouter.getMaxGasLimit() + 1;

        vm.startPrank(user);
        LinkTokenInterface(link).approve(address(compliantProxy), compliantRouter.getFee());
        vm.expectRevert(abi.encodeWithSignature("CompliantRouter__MaxGasLimitExceeded()"));
        (bool success,) = address(compliantProxy).call(
            abi.encodeWithSignature("requestKycStatus(address,address,uint64)", user, address(logic), gasLimit)
        );
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                UTILITY
    //////////////////////////////////////////////////////////////*/
    function _requestKycStatus(address caller, uint256 linkApprovalAmount, address requestedAddress, address logic)
        internal
        returns (uint256)
    {
        vm.prank(caller);
        LinkTokenInterface(link).approve(address(compliantProxy), linkApprovalAmount);
        vm.prank(caller);
        (, bytes memory retData) = address(compliantProxy).call(
            abi.encodeWithSignature(
                "requestKycStatus(address,address,uint64)", requestedAddress, logic, defaultGasLimit
            )
        );
        uint256 actualFee = abi.decode(retData, (uint256));

        return actualFee;
    }
}
