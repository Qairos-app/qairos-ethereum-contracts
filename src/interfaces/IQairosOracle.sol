// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IQairosOracle {
    event ThreatRaised(uint8 level, uint16 bits, address solver);

    /// @notice Called by QairosCanary when a rung is broken.
    function report(uint16 bits, bool armed, address solver) external;

    /// @notice 0 = nominal. +1 per broken armed rung (128-bit and up). Max 5.
    function threatLevel() external view returns (uint8);

    function rungBroken(uint16 bits) external view returns (bool);

    function lastBreak() external view returns (uint16 bits, uint64 ts);

    /// @notice Timestamp of the first armed break, or 0 if none. Ark commitments before this time are pre-Moment.
    function firstBreakTime() external view returns (uint64);
}
