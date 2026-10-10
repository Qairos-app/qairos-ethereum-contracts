// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {Rungs} from "./Rungs.sol";
import {QairosOracle} from "../src/QairosOracle.sol";
import {QairosCanary} from "../src/QairosCanary.sol";
import {QairosArk} from "../src/QairosArk.sol";
import {QairosVault} from "../src/QairosVault.sol";
import {QairosMarket} from "../src/QairosMarket.sol";
import {QairosInsurance} from "../src/QairosInsurance.sol";

/// @notice forge script script/Deploy.s.sol --rpc-url $RPC_URL --account deployer --broadcast
contract Deploy is Script, Rungs {
    function run() external {
        _loadRungs();
        vm.startBroadcast();

        QairosOracle oracle = new QairosOracle();
        QairosCanary canary = new QairosCanary(oracle);
        oracle.setCanary(address(canary));

        for (uint256 i = 0; i < rungs.length; i++) {
            RungData memory r = rungs[i];
            canary.addRung(r.bits, r.armed, r.p, r.a, r.b, r.gx, r.gy, r.qx, r.qy, r.label);
        }

        QairosArk ark = new QairosArk(oracle);
        QairosVault vault = new QairosVault(oracle, ark, 1);
        QairosMarket market = new QairosMarket(oracle);
        market.createMarket(128, uint64(block.timestamp + 450 days), "Will the 128-bit rung break before the deadline?");
        market.createMarket(256, uint64(block.timestamp + 1180 days), "Will the 256-bit rung break before the deadline?");
        market.createMarket(64, uint64(block.timestamp + 90 days), "Will the 64-bit training rung break within 90 days?");
        QairosInsurance insurance = new QairosInsurance(oracle, market, 1);

        vm.stopBroadcast();

        console2.log("QairosOracle    ", address(oracle));
        console2.log("QairosCanary    ", address(canary));
        console2.log("QairosArk       ", address(ark));
        console2.log("QairosVault     ", address(vault));
        console2.log("QairosMarket    ", address(market));
        console2.log("QairosInsurance ", address(insurance));
    }
}
