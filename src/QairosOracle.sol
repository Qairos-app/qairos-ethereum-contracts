// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IQairosOracle} from "./interfaces/IQairosOracle.sol";

/// @title QairosOracle
/// @notice Read-only threat indicator for quantum capability against elliptic-curve cryptography.
///         The level rises by one each time an armed QairosCanary rung is broken. Only the canary can report.
contract QairosOracle is IQairosOracle {
    uint8 public constant MAX_LEVEL = 5;

    address public immutable deployer;
    address public canary;

    uint8 private _level;
    uint16 private _lastBits;
    uint64 private _lastTs;
    uint64 private _firstBreakTs;
    mapping(uint16 => bool) private _broken;

    error NotCanary();
    error CanaryAlreadySet();
    error NotDeployer();

    constructor() {
        deployer = msg.sender;
    }

    /// @notice Binds the canary once. After this call the oracle has no admin.
    function setCanary(address canary_) external {
        if (msg.sender != deployer) revert NotDeployer();
        if (canary != address(0)) revert CanaryAlreadySet();
        canary = canary_;
    }

    /// @inheritdoc IQairosOracle
    function report(uint16 bits, bool armed, address solver) external {
        if (msg.sender != canary) revert NotCanary();
        _broken[bits] = true;
        if (!armed) return;
        if (_level < MAX_LEVEL) _level += 1;
        _lastBits = bits;
        _lastTs = uint64(block.timestamp);
        if (_firstBreakTs == 0) _firstBreakTs = uint64(block.timestamp);
        emit ThreatRaised(_level, bits, solver);
    }

    function threatLevel() external view returns (uint8) {
        return _level;
    }

    function rungBroken(uint16 bits) external view returns (bool) {
        return _broken[bits];
    }

    function lastBreak() external view returns (uint16 bits, uint64 ts) {
        return (_lastBits, _lastTs);
    }

    function firstBreakTime() external view returns (uint64) {
        return _firstBreakTs;
    }
}
