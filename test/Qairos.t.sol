// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, Vm} from "forge-std/Test.sol";
import {Rungs} from "../script/Rungs.sol";
import {Vectors} from "./Vectors.sol";
import {QairosMath} from "../src/lib/QairosMath.sol";
import {QairosOracle} from "../src/QairosOracle.sol";
import {IQairosOracle} from "../src/interfaces/IQairosOracle.sol";
import {QairosCanary} from "../src/QairosCanary.sol";
import {QairosArk} from "../src/QairosArk.sol";
import {QairosGuard} from "../src/QairosGuard.sol";
import {QairosVault} from "../src/QairosVault.sol";
import {QairosMarket} from "../src/QairosMarket.sol";
import {QairosInsurance} from "../src/QairosInsurance.sol";

contract ECHarness {
    function mul(uint256 p, uint256 a, uint256 b, uint256 k, uint256 gx, uint256 gy)
        external
        view
        returns (uint256, uint256, bool)
    {
        return QairosMath.mul(QairosMath.Curve(p, a, b), k, gx, gy);
    }
}

contract QairosTest is Test, Rungs {
    QairosOracle oracle;
    QairosCanary canary;
    QairosArk ark;
    QairosVault vault;
    QairosMarket market;
    QairosInsurance insurance;

    address solver = makeAddr("solver");
    address thief = makeAddr("thief");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint256 constant K16 = 21588; // planted key of training-16 (tools/params.py)
    uint256 armedTestRung; // training-16 curve re-registered as armed, for flow tests

    function setUp() public {
        _loadRungs();
        oracle = new QairosOracle();
        canary = new QairosCanary(oracle);
        oracle.setCanary(address(canary));
        for (uint256 i = 0; i < rungs.length; i++) {
            RungData memory r = rungs[i];
            canary.addRung(r.bits, r.armed, r.p, r.a, r.b, r.gx, r.gy, r.qx, r.qy, r.label);
        }
        RungData memory t = rungs[0];
        armedTestRung = canary.addRung(17, true, t.p, t.a, t.b, t.gx, t.gy, t.qx, t.qy, "armed-test");

        ark = new QairosArk(oracle);
        vault = new QairosVault(oracle, ark, 1);
        market = new QairosMarket(oracle);
        market.createMarket(17, uint64(block.timestamp + 30 days), "armed-test before deadline?");
        market.createMarket(256, uint64(block.timestamp + 365 days), "256 before deadline?");
        insurance = new QairosInsurance(oracle, market, 1);

        vm.deal(solver, 10 ether);
        vm.deal(thief, 10 ether);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    function _solve(uint256 id, uint256 k, address who) internal {
        bytes32 salt = keccak256(abi.encode(who, id));
        bytes32 c = canary.commitmentFor(id, k, who, salt);
        vm.prank(who);
        canary.commit(c);
        vm.roll(vm.getBlockNumber() + 1);
        vm.warp(vm.getBlockTimestamp() + 12);
        vm.prank(who);
        canary.reveal(id, k, salt);
    }

    // ---------------- QairosMath ----------------

    function test_ladderLoaded() public view {
        assertEq(canary.rungCount(), 13);
        assertEq(canary.rung(11).label, "secp256k1");
        assertTrue(canary.rung(11).armed);
        assertFalse(canary.rung(0).armed);
    }

    function test_secp256k1_matchesForgeWallet() public {
        ECHarness h = new ECHarness();
        uint256 pk = 0xA11CE5EED;
        Vm.Wallet memory w = vm.createWallet(pk);
        RungData memory r = rungs[11];
        (uint256 x, uint256 y, bool inf) = h.mul(r.p, r.a, r.b, pk, r.gx, r.gy);
        assertFalse(inf);
        assertEq(x, w.publicKeyX);
        assertEq(y, w.publicKeyY);
    }

    function test_armedCurves_matchPythonVectors() public {
        ECHarness h = new ECHarness();
        Vectors.V[4] memory v = [Vectors.secp128r1(), Vectors.secp160k1(), Vectors.secp192k1(), Vectors.secp224k1()];
        for (uint256 i = 0; i < 4; i++) {
            RungData memory r = rungs[7 + i];
            (uint256 x, uint256 y,) = h.mul(r.p, r.a, r.b, v[i].k, r.gx, r.gy);
            assertEq(x, v[i].qx);
            assertEq(y, v[i].qy);
        }
    }

    function test_verify_trainingPlantedKey() public view {
        assertTrue(canary.verify(0, K16));
        assertFalse(canary.verify(0, K16 + 1));
        assertFalse(canary.verify(0, 0));
    }

    /// @dev Keys found by the in-browser BSGS solver (app) must verify on-chain too.
    function test_verify_browserSolverOutputs() public view {
        assertTrue(canary.verify(0, 21588)); // training-16
        assertTrue(canary.verify(1, 4257339)); // training-24
        assertTrue(canary.verify(2, 1893215745)); // training-32
        assertTrue(canary.verify(3, 422858361627)); // training-40
    }

    // ---------------- QairosCanary ----------------

    function test_claimTrainingRung_paysAndDoesNotRaiseLevel() public {
        canary.fund{value: 1 ether}(0);
        uint256 before = solver.balance;
        _solve(0, K16, solver);
        assertEq(solver.balance - before, 1 ether);
        assertTrue(canary.rung(0).broken);
        assertEq(canary.rung(0).solver, solver);
        assertTrue(oracle.rungBroken(16));
        assertEq(oracle.threatLevel(), 0);
        assertEq(oracle.firstBreakTime(), 0);
    }

    function test_revert_wrongKey() public {
        bytes32 salt = bytes32(uint256(1));
        bytes32 c = canary.commitmentFor(0, 1234, solver, salt);
        vm.prank(solver);
        canary.commit(c);
        vm.roll(vm.getBlockNumber() + 1);
        vm.prank(solver);
        vm.expectRevert(QairosCanary.WrongKey.selector);
        canary.reveal(0, 1234, salt);
    }

    function test_revert_revealSameBlock() public {
        bytes32 salt = bytes32(uint256(1));
        bytes32 c = canary.commitmentFor(0, K16, solver, salt);
        vm.startPrank(solver);
        canary.commit(c);
        vm.expectRevert(QairosCanary.RevealTooEarly.selector);
        canary.reveal(0, K16, salt);
        vm.stopPrank();
    }

    function test_frontRunnerCannotStealReveal() public {
        bytes32 salt = bytes32(uint256(9));
        bytes32 c = canary.commitmentFor(0, K16, solver, salt);
        vm.prank(solver);
        canary.commit(c);
        vm.roll(vm.getBlockNumber() + 1);
        // thief copies k and salt from the mempool, but has no commitment bound to its own address
        vm.prank(thief);
        vm.expectRevert(QairosCanary.NoCommit.selector);
        canary.reveal(0, K16, salt);
    }

    function test_revert_doubleClaim() public {
        _solve(0, K16, solver);
        vm.expectRevert(QairosCanary.AlreadyBroken.selector);
        canary.fund{value: 1}(0);
    }

    function test_onlyCuratorAddsRungs_andRenounce() public {
        RungData memory t = rungs[0];
        vm.prank(thief);
        vm.expectRevert(QairosCanary.NotCurator.selector);
        canary.addRung(16, true, t.p, t.a, t.b, t.gx, t.gy, t.qx, t.qy, "x");
        canary.renounceCuration();
        vm.expectRevert(QairosCanary.NotCurator.selector);
        canary.addRung(16, true, t.p, t.a, t.b, t.gx, t.gy, t.qx, t.qy, "x");
    }

    function test_revert_offCurvePoint() public {
        RungData memory t = rungs[0];
        vm.expectRevert(QairosCanary.BadRung.selector);
        canary.addRung(16, false, t.p, t.a, t.b, t.gx, t.gy, t.qx, t.qy + 1, "bad");
    }

    // ---------------- QairosOracle ----------------

    function test_armedBreak_raisesLevel() public {
        bytes32 salt = bytes32(uint256(5));
        bytes32 c = canary.commitmentFor(armedTestRung, K16, solver, salt);
        vm.prank(solver);
        canary.commit(c);
        vm.roll(vm.getBlockNumber() + 1);
        vm.expectEmit(address(oracle));
        emit IQairosOracle.ThreatRaised(1, 17, solver);
        vm.prank(solver);
        canary.reveal(armedTestRung, K16, salt);
        assertEq(oracle.threatLevel(), 1);
        (uint16 bits, uint64 ts) = oracle.lastBreak();
        assertEq(bits, 17);
        assertEq(ts, block.timestamp);
        assertEq(oracle.firstBreakTime(), block.timestamp);
    }

    function test_oracle_onlyCanaryReports() public {
        vm.expectRevert(QairosOracle.NotCanary.selector);
        oracle.report(256, true, thief);
        vm.expectRevert(QairosOracle.CanaryAlreadySet.selector);
        oracle.setCanary(thief);
    }

    // ---------------- QairosArk + QairosVault (Qairos Breaker) ----------------

    bytes constant PQ_PUB = hex"0a1b2c3d4e5f60718293a4b5c6d7e8f9"; // stands in for a 1312-byte ML-DSA-44 key
    bytes32 constant ARK_SALT = keccak256("alice-offline-salt");

    function test_vault_fullRecoveryFlow() public {
        // before the Qairos Moment: alice registers in the Ark and deposits
        bytes32 ac = ark.commitmentFor(PQ_PUB, ARK_SALT, alice);
        vm.startPrank(alice);
        ark.commit(ac);
        vault.deposit{value: 40 ether}();
        vault.withdraw(5 ether);
        vm.stopPrank();
        assertTrue(ark.isPreMoment(alice));

        // Qairos Moment: armed rung breaks, breaker trips
        _solve(armedTestRung, K16, solver);
        assertTrue(vault.breakerTripped());

        // a quantum thief holding alice's ECDSA key can no longer withdraw
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(QairosGuard.QuantumBreakerTripped.selector, uint8(1), uint8(1)));
        vault.withdraw(1 ether);

        // thief also cannot rotate alice's ark entry
        vm.prank(alice);
        vm.expectRevert(QairosArk.MomentPassed.selector);
        ark.commit(bytes32(uint256(666)));

        // thief guesses a preimage: rejected
        bytes memory fakePub = hex"deadbeef";
        bytes32 tc = vault.recoveryCommitment(alice, thief, fakePub, ARK_SALT);
        vm.prank(thief);
        vault.commitRecovery(tc);
        vm.roll(vm.getBlockNumber() + 1);
        vm.prank(thief);
        vm.expectRevert(QairosVault.ArkMismatch.selector);
        vault.recover(alice, thief, fakePub, ARK_SALT);

        // real owner recovers to a fresh address with the pre-Moment preimage
        address safeAddr = makeAddr("alice-pq-wallet");
        vault.commitRecovery(vault.recoveryCommitment(alice, safeAddr, PQ_PUB, ARK_SALT));
        vm.roll(vm.getBlockNumber() + 1);
        vault.recover(alice, safeAddr, PQ_PUB, ARK_SALT);
        assertEq(safeAddr.balance, 35 ether);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_vault_recoveryRequiresCommitInEarlierBlock() public {
        bytes32 ac = ark.commitmentFor(PQ_PUB, ARK_SALT, alice);
        vm.prank(alice);
        ark.commit(ac);
        _solve(armedTestRung, K16, solver);
        bytes32 c = vault.recoveryCommitment(alice, bob, PQ_PUB, ARK_SALT);
        vault.commitRecovery(c);
        vm.expectRevert(QairosVault.RecoveryTooEarly.selector);
        vault.recover(alice, bob, PQ_PUB, ARK_SALT);
    }

    function test_ark_postMomentEntryIsNotTrusted() public {
        _solve(armedTestRung, K16, solver);
        vm.warp(vm.getBlockTimestamp() + 1);
        bytes32 bc = ark.commitmentFor(PQ_PUB, ARK_SALT, bob);
        vm.prank(bob);
        ark.commit(bc);
        assertTrue(ark.verify(bob, PQ_PUB, ARK_SALT));
        assertFalse(ark.isPreMoment(bob));
        vault.commitRecovery(vault.recoveryCommitment(bob, bob, PQ_PUB, ARK_SALT));
        vm.roll(vm.getBlockNumber() + 1);
        vm.expectRevert(QairosVault.NotPreMoment.selector);
        vault.recover(bob, bob, PQ_PUB, ARK_SALT);
    }

    // ---------------- QairosMarket ----------------

    function test_market_yesWinsWhenRungBreaks() public {
        vm.prank(alice);
        market.buy{value: 3 ether}(0, true);
        vm.prank(bob);
        market.buy{value: 9 ether}(0, false);
        assertEq(market.impliedYesBps(0), 2500);

        _solve(armedTestRung, K16, solver);
        market.settle(0);
        assertTrue(market.market(0).yesWon);

        uint256 before = alice.balance;
        vm.prank(alice);
        market.claim(0);
        assertEq(alice.balance - before, 12 ether);

        vm.prank(bob);
        vm.expectRevert(QairosMarket.NothingToClaim.selector);
        market.claim(0);
    }

    function test_market_noWinsAtDeadline_andClosesBuys() public {
        vm.prank(alice);
        market.buy{value: 2 ether}(0, true);
        vm.prank(bob);
        market.buy{value: 6 ether}(0, false);
        vm.expectRevert(QairosMarket.NotSettleable.selector);
        market.settle(0);
        vm.warp(vm.getBlockTimestamp() + 31 days);
        vm.prank(alice);
        vm.expectRevert(QairosMarket.Closed.selector);
        market.buy{value: 1 ether}(0, true);
        uint256 before = bob.balance;
        vm.prank(bob);
        market.claim(0);
        assertEq(bob.balance - before, 8 ether);
    }

    // ---------------- QairosInsurance ----------------

    function test_insurance_pricingFollowsMarket() public {
        assertEq(insurance.rateBps(), 40 + 250); // empty market => 50% => 290 bps
        vm.prank(alice);
        market.buy{value: 1 ether}(1, true);
        vm.prank(bob);
        market.buy{value: 9 ether}(1, false);
        assertEq(insurance.rateBps(), 40 + 50); // 10% yes
        assertEq(insurance.quote(25 ether, 2), 25 ether * 90 * 2 / 10_000);
    }

    function test_insurance_paysOnQairosMoment() public {
        vm.prank(bob);
        insurance.underwrite{value: 50 ether}();
        uint256 premium = insurance.quote(20 ether, 2);
        vm.prank(alice);
        uint256 id = insurance.buyPolicy{value: premium}(20 ether, 2);
        assertEq(insurance.lockedCoverage(), 20 ether);

        // underwriter cannot pull locked capital
        uint256 s = insurance.shares(bob);
        vm.prank(bob);
        vm.expectRevert(QairosInsurance.Locked.selector);
        insurance.withdraw(s);

        vm.prank(alice);
        vm.expectRevert(QairosInsurance.NotCovered.selector);
        insurance.claim(id);

        _solve(armedTestRung, K16, solver);
        uint256 before = alice.balance;
        vm.prank(alice);
        insurance.claim(id);
        assertEq(alice.balance - before, 20 ether);
        assertEq(insurance.lockedCoverage(), 0);
    }

    function test_insurance_expireReleasesCapital() public {
        vm.prank(bob);
        insurance.underwrite{value: 10 ether}();
        uint256 premium = insurance.quote(5 ether, 1);
        vm.prank(alice);
        uint256 id = insurance.buyPolicy{value: premium}(5 ether, 1);
        vm.expectRevert(QairosInsurance.StillActive.selector);
        insurance.expire(id);
        vm.warp(vm.getBlockTimestamp() + 366 days);
        insurance.expire(id);
        uint256 s = insurance.shares(bob);
        uint256 before = bob.balance;
        vm.prank(bob);
        insurance.withdraw(s);
        assertEq(bob.balance - before, 10 ether + premium);
    }

    function test_revert_wrongPremium() public {
        vm.prank(bob);
        insurance.underwrite{value: 10 ether}();
        uint256 q = insurance.quote(1 ether, 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(QairosInsurance.WrongPremium.selector, q));
        insurance.buyPolicy{value: 1}(1 ether, 1);
    }
}


