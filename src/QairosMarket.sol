// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IQairosOracle} from "./interfaces/IQairosOracle.sol";

/// @title QairosMarket
/// @notice Parimutuel prediction markets on "will rung X be broken before deadline?". Settlement reads QairosOracle
///         directly: YES as soon as the rung is broken, NO once the deadline passes. No votes, no disputes.
contract QairosMarket {
    struct Market {
        uint16 bits;
        uint64 deadline;
        bool settled;
        bool yesWon;
        uint256 yesPool;
        uint256 noPool;
        string question;
    }

    IQairosOracle public immutable oracle;
    address public immutable creator;
    Market[] private _markets;
    mapping(uint256 => mapping(address => uint256)) public yesStake;
    mapping(uint256 => mapping(address => uint256)) public noStake;

    uint256 private _lock = 1;

    event MarketCreated(uint256 indexed id, uint16 bits, uint64 deadline, string question);
    event Bought(uint256 indexed id, address indexed buyer, bool yes, uint256 amount);
    event Settled(uint256 indexed id, bool yesWon);
    event Claimed(uint256 indexed id, address indexed account, uint256 payout);

    error NotCreator();
    error Closed();
    error NotSettleable();
    error NotSettled();
    error NothingToClaim();
    error Reentrancy();
    error TransferFailed();

    modifier nonReentrant() {
        if (_lock != 1) revert Reentrancy();
        _lock = 2;
        _;
        _lock = 1;
    }

    constructor(IQairosOracle oracle_) {
        oracle = oracle_;
        creator = msg.sender;
    }

    function createMarket(uint16 bits, uint64 deadline, string calldata question) external returns (uint256 id) {
        if (msg.sender != creator) revert NotCreator();
        id = _markets.length;
        _markets.push(Market(bits, deadline, false, false, 0, 0, question));
        emit MarketCreated(id, bits, deadline, question);
    }

    function buy(uint256 id, bool yes) external payable {
        Market storage m = _markets[id];
        if (m.settled || block.timestamp >= m.deadline || oracle.rungBroken(m.bits)) revert Closed();
        if (yes) {
            m.yesPool += msg.value;
            yesStake[id][msg.sender] += msg.value;
        } else {
            m.noPool += msg.value;
            noStake[id][msg.sender] += msg.value;
        }
        emit Bought(id, msg.sender, yes, msg.value);
    }

    function settle(uint256 id) public {
        Market storage m = _markets[id];
        if (m.settled) return;
        if (oracle.rungBroken(m.bits)) {
            m.yesWon = true;
        } else if (block.timestamp >= m.deadline) {
            m.yesWon = false;
        } else {
            revert NotSettleable();
        }
        m.settled = true;
        emit Settled(id, m.yesWon);
    }

    /// @notice Winners split the whole pot pro rata. If nobody backed the winning side, everyone is refunded.
    function claim(uint256 id) external nonReentrant {
        Market storage m = _markets[id];
        if (!m.settled) settle(id);
        uint256 y = yesStake[id][msg.sender];
        uint256 n = noStake[id][msg.sender];
        uint256 winPool = m.yesWon ? m.yesPool : m.noPool;
        uint256 total = m.yesPool + m.noPool;
        uint256 payout;
        if (winPool == 0) {
            payout = y + n;
        } else {
            uint256 stake = m.yesWon ? y : n;
            payout = stake * total / winPool;
        }
        if (payout == 0) revert NothingToClaim();
        yesStake[id][msg.sender] = 0;
        noStake[id][msg.sender] = 0;
        (bool ok,) = msg.sender.call{value: payout}("");
        if (!ok) revert TransferFailed();
        emit Claimed(id, msg.sender, payout);
    }

    /// @notice Implied probability of YES in basis points (0-10000). 5000 when the market is empty.
    function impliedYesBps(uint256 id) public view returns (uint256) {
        Market storage m = _markets[id];
        uint256 total = m.yesPool + m.noPool;
        if (total == 0) return 5000;
        return m.yesPool * 10_000 / total;
    }

    function market(uint256 id) external view returns (Market memory) {
        return _markets[id];
    }

    function marketCount() external view returns (uint256) {
        return _markets.length;
    }
}
