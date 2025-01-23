// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {BaseTest} from "../../BaseTest.t.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {IEverestConsumer} from "@everest/contracts/interfaces/IEverestConsumer.sol";

contract GetFeeTest is BaseTest {
    uint256 internal constant WAD_PRECISION = 1e18;
    uint256 internal constant COMPLIANT_FEE = 5e7; // $0.5

    function test_compliant_getFee() public view {
        /// @dev get price of LINK in USD
        (, int256 price,,,) = AggregatorV3Interface(linkUsdFeed).latestRoundData();

        /// @dev get Everest and Automation fees
        uint256 everestFee = compliantRouter.getEverestFee();
        uint256 automationFee = compliantRouter.getAutomationFee();

        /// @dev get the totalFee
        uint256 totalFee = compliantRouter.getFee();
        uint256 compliantFee = totalFee - (everestFee + automationFee);

        /// @dev calculate expected fee
        uint256 expectedFee = (COMPLIANT_FEE * WAD_PRECISION) / uint256(price);

        assertEq(compliantFee, expectedFee);
        assertEq(compliantFee, compliantRouter.getCompliantFee());
    }
}
