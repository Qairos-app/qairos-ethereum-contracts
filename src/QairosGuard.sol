// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IQairosOracle} from "./interfaces/IQairosOracle.sol";

/// @title QairosGuard (Qairos Breaker)
/// @notice Drop-in circuit breaker. Inherit it, set a threshold, and tag functions with `quantumSafe`.
///         Once QairosOracle.threatLevel() reaches the threshold, tagged functions stop accepting ECDSA-only callers.
abstract contract QairosGuard {
    IQairosOracle public immutable qOracle;
    uint8 public immutable tripLevel;

    error QuantumBreakerTripped(uint8 level, uint8 threshold);

    constructor(IQairosOracle oracle_, uint8 tripLevel_) {
        require(tripLevel_ >= 1, "QairosGuard: threshold >= 1");
        qOracle = oracle_;
        tripLevel = tripLevel_;
    }

    function breakerTripped() public view returns (bool) {
        return qOracle.threatLevel() >= tripLevel;
    }

    modifier quantumSafe() {
        uint8 l = qOracle.threatLevel();
        if (l >= tripLevel) revert QuantumBreakerTripped(l, tripLevel);
        _;
    }

    modifier onlyWhenTripped() {
        require(breakerTripped(), "QairosGuard: not tripped");
        _;
    }
}
