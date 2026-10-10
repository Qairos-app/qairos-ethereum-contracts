// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IQairosOracle} from "./interfaces/IQairosOracle.sol";

/// @title QairosArk
/// @notice Pre-registration of post-quantum ownership. An account stores keccak256(pqPublicKey || salt || account)
///         today. If ECDSA falls, revealing a preimage that was committed before the first armed QairosCanary break
///         proves ownership in a way a quantum attacker cannot forge after the fact.
contract QairosArk {
    struct Entry {
        bytes32 commitment;
        uint64 committedAt;
        uint64 blockNumber;
    }

    IQairosOracle public immutable oracle;
    mapping(address => Entry) public entries;
    uint256 public totalEntries;

    event Committed(address indexed account, bytes32 commitment, uint64 timestamp, bool preQairosMoment);

    error MomentPassed();

    constructor(IQairosOracle oracle_) {
        oracle = oracle_;
    }

    /// @notice Store or rotate a commitment. Rotation is closed once the Qairos Moment is recorded by the oracle,
    ///         so a quantum attacker holding the ECDSA key cannot overwrite a pre-Moment entry.
    function commit(bytes32 commitment) external {
        bool pre = oracle.firstBreakTime() == 0;
        Entry storage e = entries[msg.sender];
        if (!pre && e.commitment != bytes32(0)) revert MomentPassed();
        if (e.commitment == bytes32(0)) totalEntries += 1;
        entries[msg.sender] = Entry(commitment, uint64(block.timestamp), uint64(block.number));
        emit Committed(msg.sender, commitment, uint64(block.timestamp), pre);
    }

    function commitmentFor(bytes calldata pqPublicKey, bytes32 salt, address account) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(pqPublicKey, salt, account));
    }

    /// @notice True when the preimage matches the stored commitment for `account`.
    function verify(address account, bytes calldata pqPublicKey, bytes32 salt) public view returns (bool) {
        bytes32 c = entries[account].commitment;
        return c != bytes32(0) && c == commitmentFor(pqPublicKey, salt, account);
    }

    /// @notice True when the account's entry predates the first armed canary break (or no break has happened).
    function isPreMoment(address account) public view returns (bool) {
        Entry memory e = entries[account];
        if (e.commitment == bytes32(0)) return false;
        uint64 q = oracle.firstBreakTime();
        return q == 0 || e.committedAt < q;
    }
}
