// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IQairosOracle} from "./interfaces/IQairosOracle.sol";
import {QairosMarket} from "./QairosMarket.sol";

/// @title QairosInsurance
/// @notice Exposure cover against the Qairos Moment. Underwriters pool ETH and earn premiums. A policy pays its full coverage
///         if the first armed QairosCanary break happens during the policy term. Price follows the QairosMarket crowd:
///         rate = BASE_BPS + impliedYes * SLOPE_BPS / 10000, per year.
contract QairosInsurance {
    struct Policy {
        address holder;
        uint128 coverage;
        uint64 start;
        uint64 expiry;
        bool closed;
    }

    uint256 public constant BASE_BPS = 40;
    uint256 public constant SLOPE_BPS = 500;
    uint256 public constant MAX_YEARS = 5;

    IQairosOracle public immutable oracle;
    QairosMarket public immutable market;
    uint256 public immutable marketId;

    uint256 public totalShares;
    mapping(address => uint256) public shares;
    uint256 public lockedCoverage;
    Policy[] public policies;

    uint256 private _lock = 1;

    event Underwritten(address indexed account, uint256 amount, uint256 shares);
    event Withdrawn(address indexed account, uint256 amount, uint256 shares);
    event PolicyBought(uint256 indexed id, address indexed holder, uint256 coverage, uint256 premium, uint64 expiry);
    event PolicyPaid(uint256 indexed id, uint256 coverage);
    event PolicyExpired(uint256 indexed id);

    error BadTerm();
    error WrongPremium(uint256 expected);
    error NoCapacity();
    error NotHolder();
    error NotCovered();
    error StillActive();
    error PolicyClosed();
    error Locked();
    error Reentrancy();
    error TransferFailed();

    modifier nonReentrant() {
        if (_lock != 1) revert Reentrancy();
        _lock = 2;
        _;
        _lock = 1;
    }

    constructor(IQairosOracle oracle_, QairosMarket market_, uint256 marketId_) {
        oracle = oracle_;
        market = market_;
        marketId = marketId_;
    }

    function rateBps() public view returns (uint256) {
        return BASE_BPS + market.impliedYesBps(marketId) * SLOPE_BPS / 10_000;
    }

    function quote(uint256 coverage, uint256 years_) public view returns (uint256) {
        return coverage * rateBps() * years_ / 10_000;
    }

    function freeCapital() public view returns (uint256) {
        uint256 bal = address(this).balance;
        return bal > lockedCoverage ? bal - lockedCoverage : 0;
    }

    function underwrite() external payable {
        uint256 assetsBefore = address(this).balance - msg.value;
        uint256 s = (totalShares == 0 || assetsBefore == 0) ? msg.value : msg.value * totalShares / assetsBefore;
        shares[msg.sender] += s;
        totalShares += s;
        emit Underwritten(msg.sender, msg.value, s);
    }

    function withdraw(uint256 s) external nonReentrant {
        uint256 amount = s * address(this).balance / totalShares;
        if (amount > freeCapital()) revert Locked();
        shares[msg.sender] -= s;
        totalShares -= s;
        _send(msg.sender, amount);
        emit Withdrawn(msg.sender, amount, s);
    }

    function buyPolicy(uint256 coverage, uint256 years_) external payable returns (uint256 id) {
        if (years_ == 0 || years_ > MAX_YEARS) revert BadTerm();
        if (oracle.firstBreakTime() != 0) revert NotCovered();
        uint256 premium = quote(coverage, years_);
        if (msg.value != premium) revert WrongPremium(premium);
        if (freeCapital() < coverage) revert NoCapacity();
        lockedCoverage += coverage;
        uint64 expiry = uint64(block.timestamp + years_ * 365 days);
        id = policies.length;
        policies.push(Policy(msg.sender, uint128(coverage), uint64(block.timestamp), expiry, false));
        emit PolicyBought(id, msg.sender, coverage, premium, expiry);
    }

    function claim(uint256 id) external nonReentrant {
        Policy storage p = policies[id];
        if (p.closed) revert PolicyClosed();
        if (msg.sender != p.holder) revert NotHolder();
        uint64 q = oracle.firstBreakTime();
        if (q == 0 || q < p.start || q > p.expiry) revert NotCovered();
        p.closed = true;
        lockedCoverage -= p.coverage;
        _send(p.holder, p.coverage);
        emit PolicyPaid(id, p.coverage);
    }

    /// @notice Releases capital of a policy whose term ended without a covered event. Callable by anyone.
    function expire(uint256 id) external {
        Policy storage p = policies[id];
        if (p.closed) revert PolicyClosed();
        if (block.timestamp <= p.expiry) revert StillActive();
        uint64 q = oracle.firstBreakTime();
        if (q != 0 && q >= p.start && q <= p.expiry) revert StillActive();
        p.closed = true;
        lockedCoverage -= p.coverage;
        emit PolicyExpired(id);
    }

    function policyCount() external view returns (uint256) {
        return policies.length;
    }

    function _send(address to, uint256 amount) private {
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}
