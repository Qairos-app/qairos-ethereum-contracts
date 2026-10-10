# Deployment Safety

Default tests run locally without a fork, external RPC or funded signing key.
No release or CI workflow broadcasts transactions.
Before any deployment, independently review source, constructor arguments, threat thresholds, toy rung parameters, authorization, gas estimates and total cost.
Use a separate operator-managed signer; never put its credential in source, package files, command history or this repository.
Review scripts/constructor assumptions before using the existing `script/Deploy.s.sol` workflow.
Historical chain-1 addresses are in deployments/ethereum-mainnet.json. Compare compiled and deployed bytecode separately before asserting equivalence.
Funding a vault, bounty, market or insurance pool is a separate irreversible transaction and is not performed by this release.
