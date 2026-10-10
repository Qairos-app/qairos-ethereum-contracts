# Qairos Ethereum Contracts

**Ethereum oracle, canary, Ark, vault, markets and insurance contracts.**

[Source](https://github.com/Qairos-app/qairos-ethereum-contracts) · [Releases](https://github.com/Qairos-app/qairos-ethereum-contracts/releases) · [Support](mailto:support@qairos.tech)

## Status
Version `0.1.0` is an experimental standalone distribution. Contracts have not been independently audited.
Quantum monitoring does not guarantee safety, and ordinary EVM wallet signatures are not post-quantum.
Local validation results are included with the initial release; no CI success, npm publication or Mainnet write is implied without separate evidence.

## Features
- Threat oracle and toy-curve canary commitment/reveal challenges.
- Sender-bound Ark commitments and a guarded ETH vault.
- Prediction markets and capital-backed insurance accounting.
- Public Mainnet deployment metadata and ABI files for six contracts.

## Quick start
Requirements: Node.js 24, pnpm 10.26.1 and Foundry 1.1.0 with Solidity 0.8.28.

```sh
git clone https://github.com/Qairos-app/qairos-ethereum-contracts.git
cd qairos-ethereum-contracts
pnpm install --frozen-lockfile
forge build
forge test
```

## Boundaries and configuration
These contracts are unaudited and experimental. Toy curves are controlled test challenges, not proof that Ethereum-scale cryptography has been broken. Mainnet deployment metadata is historical public data, not a new deployment or a verified-bytecode claim. Vault recovery material is bearer material; anyone holding it may be able to act. Never broadcast deployment scripts automatically.

## Quality and releases
Run `pnpm run validate`. Run `pnpm run release:package` to create the versioned `.tgz` and SHA-256 checksum.
Follow [docs/RELEASE.md](docs/RELEASE.md) before tagging. GitHub releases and npm registry publication are separate operations.
See [docs/DIAGNOSTICS.md](docs/DIAGNOSTICS.md) for reproducible checks and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for component boundaries.

## Community
- [Contributing](CONTRIBUTING.md)
- [Code of conduct](CODE_OF_CONDUCT.md)
- [Security reporting](SECURITY.md)
- [Support](SUPPORT.md)
- [Governance](GOVERNANCE.md)
- [Changelog](CHANGELOG.md)

## License
MIT for Qairos-authored source; retain upstream and per-file notices. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
Brand assets do not grant endorsement or trademark rights.
