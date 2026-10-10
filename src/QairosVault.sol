// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IQairosOracle} from "./interfaces/IQairosOracle.sol";
import {QairosGuard} from "./QairosGuard.sol";
import {QairosArk} from "./QairosArk.sol";

/// @title QairosVault
/// @notice Reference integration of QairosGuard + QairosArk. Normal ECDSA withdrawals work while the breaker is
///         open. Once tripped, funds move only through Ark recovery: a two-step commit-reveal of the pre-Moment
///         post-quantum preimage. A quantum attacker who derived the ECDSA key still cannot know that preimage.
contract QairosVault is QairosGuard {
    QairosArk public immutable ark;
    mapping(address => uint256) public balanceOf;

    /// @dev recovery commitment => block number
    mapping(bytes32 => uint256) public recoveryCommitBlock;

    uint256 private _lock = 1;

    event Deposited(address indexed account, uint256 amount);
    event Withdrawn(address indexed account, uint256 amount);
    event RecoveryCommitted(bytes32 commitment);
    event Recovered(address indexed account, address indexed to, uint256 amount);

    error Reentrancy();
    error Insufficient();
    error NoRecoveryCommit();
    error RecoveryTooEarly();
    error ArkMismatch();
    error NotPreMoment();
    error TransferFailed();

    modifier nonReentrant() {
        if (_lock != 1) revert Reentrancy();
        _lock = 2;
        _;
        _lock = 1;
    }

    constructor(IQairosOracle oracle_, QairosArk ark_, uint8 tripLevel_) QairosGuard(oracle_, tripLevel_) {
        ark = ark_;
    }

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external quantumSafe nonReentrant {
        if (balanceOf[msg.sender] < amount) revert Insufficient();
        balanceOf[msg.sender] -= amount;
        _send(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function recoveryCommitment(address account, address to, bytes calldata pqPublicKey, bytes32 salt)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(account, to, keccak256(pqPublicKey), salt));
    }

    /// @notice Step 1 of recovery. Anyone may submit; the commitment hides the preimage and destination.
    function commitRecovery(bytes32 commitment) external onlyWhenTripped {
        if (recoveryCommitBlock[commitment] == 0) recoveryCommitBlock[commitment] = block.number;
        emit RecoveryCommitted(commitment);
    }

    /// @notice Step 2 of recovery, in a later block. Moves the whole balance of `account` to `to`.
    function recover(address account, address to, bytes calldata pqPublicKey, bytes32 salt)
        external
        onlyWhenTripped
        nonReentrant
    {
        bytes32 c = recoveryCommitment(account, to, pqPublicKey, salt);
        uint256 cb = recoveryCommitBlock[c];
        if (cb == 0) revert NoRecoveryCommit();
        if (cb >= block.number) revert RecoveryTooEarly();
        if (!ark.verify(account, pqPublicKey, salt)) revert ArkMismatch();
        if (!ark.isPreMoment(account)) revert NotPreMoment();

        uint256 amount = balanceOf[account];
        balanceOf[account] = 0;
        delete recoveryCommitBlock[c];
        _send(to, amount);
        emit Recovered(account, to, amount);
    }

    function _send(address to, uint256 amount) private {
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
    }
}
