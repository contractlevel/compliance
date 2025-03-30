// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {BaseTest, LinkTokenInterface, console2} from "../../BaseTest.t.sol";
import {IEverestConsumer} from "@everest/contracts/interfaces/IEverestConsumer.sol";

contract WithdrawFeesTest is BaseTest {
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
    function test_compliant_withdrawFees_success() public {
        /// @dev call requestKycStatus as user to generate fees
        vm.prank(user);
        (, bytes memory feeRetData) = address(compliantProxy).call(
            abi.encodeWithSignature("requestKycStatus(address,address,uint64)", user, address(logic))
        );
        uint256 fee = abi.decode(feeRetData, (uint256));

        uint256 compliantFee = fee - compliantRouter.getEverestFee() - compliantRouter.getAutomationFee();

        uint256 balanceBefore = LinkTokenInterface(link).balanceOf(owner);

        /// @dev assert correct fees to withdraw exists
        (, bytes memory withdrawDataBefore) =
            address(compliantProxy).call(abi.encodeWithSignature("getCompliantFeesToWithdraw()"));
        uint256 feesToWithdrawBefore = abi.decode(withdrawDataBefore, (uint256));
        assertEq(compliantFee, feesToWithdrawBefore);

        /// @dev withdraw fees
        vm.prank(owner);
        (bool success,) = address(compliantProxy).call(abi.encodeWithSignature("withdrawFees()"));
        require(success, "delegate call to withdrawFees() failed");

        uint256 balanceAfter = LinkTokenInterface(link).balanceOf(owner);

        (, bytes memory withdrawDataAfter) =
            address(compliantProxy).call(abi.encodeWithSignature("getCompliantFeesToWithdraw()"));
        uint256 feesToWithdrawAfter = abi.decode(withdrawDataAfter, (uint256));

        assertEq(feesToWithdrawAfter, 0);
        assertEq(balanceAfter, balanceBefore + compliantFee);
    }

    function test_compliant_withdrawFees_revertsWhen_notOwner() public {
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", user));
        (bool success,) = address(compliantProxy).call(abi.encodeWithSignature("withdrawFees()"));
    }

    function test_compliant_withdrawFees_revertsWhen_notProxy() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("CompliantRouter__OnlyProxy()"));
        compliantRouter.withdrawFees();
    }
}
