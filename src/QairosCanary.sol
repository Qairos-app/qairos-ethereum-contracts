// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {QairosMath} from "./lib/QairosMath.sol";
import {IQairosOracle} from "./interfaces/IQairosOracle.sol";

/// @title QairosCanary
/// @notice A ladder of elliptic-curve discrete-log bounties. Each rung publishes a curve, a base point G and a
///         target point Q. Whoever finds k with k*G == Q claims the bounty through commit-reveal.
///         The contract verifies the answer itself; no judges. Armed rungs (128-bit and up) raise the QairosOracle level.
contract QairosCanary {
    using QairosMath for QairosMath.Curve;

    struct Rung {
        uint16 bits;
        bool armed;
        bool broken;
        address solver;
        uint64 brokenAt;
        uint256 bounty;
        QairosMath.Curve curve;
        uint256 gx;
        uint256 gy;
        uint256 qx;
        uint256 qy;
        string label;
    }

    IQairosOracle public immutable oracle;
    address public curator;
    Rung[] private _rungs;

    /// @dev committer => commitment => block number of the commit
    mapping(address => mapping(bytes32 => uint256)) public commitBlock;

    uint256 private _lock = 1;

    event RungAdded(uint256 indexed id, uint16 bits, bool armed, string label);
    event Funded(uint256 indexed id, address indexed from, uint256 amount);
    event Committed(address indexed solver, bytes32 commitment);
    event RungBroken(uint256 indexed id, uint16 bits, address indexed solver, uint256 k, uint256 bounty);

    error NotCurator();
    error BadRung();
    error AlreadyBroken();
    error NoCommit();
    error RevealTooEarly();
    error WrongKey();
    error Reentrancy();
    error PayoutFailed();

    modifier nonReentrant() {
        if (_lock != 1) revert Reentrancy();
        _lock = 2;
        _;
        _lock = 1;
    }

    constructor(IQairosOracle oracle_) {
        oracle = oracle_;
        curator = msg.sender;
    }

    /// @notice Adds a rung. Rungs are immutable once added. Curation can be renounced.
    function addRung(
        uint16 bits,
        bool armed,
        uint256 p,
        uint256 a,
        uint256 b,
        uint256 gx,
        uint256 gy,
        uint256 qx,
        uint256 qy,
        string calldata label
    ) external returns (uint256 id) {
        if (msg.sender != curator) revert NotCurator();
        QairosMath.Curve memory c = QairosMath.Curve(p, a, b);
        if (p < 3 || !c.isOnCurve(gx, gy) || !c.isOnCurve(qx, qy)) revert BadRung();
        id = _rungs.length;
        _rungs.push(Rung(bits, armed, false, address(0), 0, 0, c, gx, gy, qx, qy, label));
        emit RungAdded(id, bits, armed, label);
    }

    function renounceCuration() external {
        if (msg.sender != curator) revert NotCurator();
        curator = address(0);
    }

    /// @notice Anyone can add ETH to a rung's bounty.
    function fund(uint256 id) external payable {
        if (id >= _rungs.length) revert BadRung();
        if (_rungs[id].broken) revert AlreadyBroken();
        _rungs[id].bounty += msg.value;
        emit Funded(id, msg.sender, msg.value);
    }

    /// @notice Step 1: commit to keccak256(abi.encode(id, k, msg.sender, salt)) without revealing k.
    function commit(bytes32 commitment) external {
        commitBlock[msg.sender][commitment] = block.number;
        emit Committed(msg.sender, commitment);
    }

    /// @notice Step 2: reveal k in a later block. Pays the bounty when k*G == Q.
    function reveal(uint256 id, uint256 k, bytes32 salt) external nonReentrant {
        if (id >= _rungs.length) revert BadRung();
        Rung storage r = _rungs[id];
        if (r.broken) revert AlreadyBroken();
        bytes32 c = commitmentFor(id, k, msg.sender, salt);
        uint256 cb = commitBlock[msg.sender][c];
        if (cb == 0) revert NoCommit();
        if (cb >= block.number) revert RevealTooEarly();
        if (!verify(id, k)) revert WrongKey();

        uint256 amount = r.bounty;
        r.broken = true;
        r.solver = msg.sender;
        r.brokenAt = uint64(block.timestamp);
        r.bounty = 0;
        delete commitBlock[msg.sender][c];

        oracle.report(r.bits, r.armed, msg.sender);
        emit RungBroken(id, r.bits, msg.sender, k, amount);

        if (amount > 0) {
            (bool ok,) = msg.sender.call{value: amount}("");
            if (!ok) revert PayoutFailed();
        }
    }

    function commitmentFor(uint256 id, uint256 k, address solver, bytes32 salt) public pure returns (bytes32) {
        return keccak256(abi.encode(id, k, solver, salt));
    }

    /// @notice Pure check, usable off-chain: is k the discrete log of Q for this rung?
    function verify(uint256 id, uint256 k) public view returns (bool) {
        Rung storage r = _rungs[id];
        if (k == 0) return false;
        (uint256 x, uint256 y, bool inf) = r.curve.mul(k, r.gx, r.gy);
        return !inf && x == r.qx && y == r.qy;
    }

    function rungCount() external view returns (uint256) {
        return _rungs.length;
    }

    function rung(uint256 id) external view returns (Rung memory) {
        return _rungs[id];
    }
}
