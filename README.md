# Farming Season (SEASON)

Farming Season is a fixed-supply ERC-20. Its constructor mints **1,000,000,000
SEASON with 18 decimals** to the deployer, once. Transfers and approvals use the
vendored OpenZeppelin Contracts v5.4.0 implementation.

| Parameter | Value |
| --- | --- |
| Solidity contract | `FarmingSeason` |
| Source | `src/FarmingSeason.sol` |
| Token name | `Farming Season` |
| Symbol | `SEASON` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None |
| Initial recipient | `msg.sender` during construction |
| Compiler | Solidity `0.8.26` |
| EVM target | Cancun |
| Build settings | Optimizer enabled, 200 runs; `bytecode_hash = "none"` |

## Behavior and assumptions

The requested custom token is an ordinary ERC-20; the brief specifies no farming
application, emissions, staking, taxes, or vesting. `INITIAL_SUPPLY` is a public
constant and the constructor is the only mint path. There is no owner, admin,
pause, blacklist, confiscation, burn entry point, proxy, or upgrade mechanism.
The deployer has the same transfer and approval permissions as every other holder.
The supply remains constant throughout the token's lifetime.

Transfers deliver the exact amount to any nonzero recipient, including contracts.
Zero-value transfers and self transfers are supported. Transfers to the zero
address and approvals to the zero spender revert. Insufficient balances or
allowances revert with OpenZeppelin's ERC-6093 custom errors. `transferFrom`
requires allowance even when the caller is the source account. A maximum
`uint256` approval is treated as unlimited and does not decrease on spending;
finite allowances decrease by the amount spent. A failed operation rolls back
all balance and allowance changes. Explicit approvals emit `Approval`; delegated
spending emits `Transfer` without a separate `Approval` event, following this
OpenZeppelin version.

The contract has no payable entry point or asset-recovery function. Holders must
check destination addresses: sending SEASON or other tokens to a contract that
cannot return them can lock them permanently. Transfers do not call recipients.

## Build and tests

Run from the repository root with Foundry and Solidity 0.8.26 installed:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x9b1c9691f86011aa05460ec65e734940f3876e49ba1d5497bd17d17d31b60491 forge test
forge fmt --check
```

Both production dependencies and the test framework are vendored as ordinary
files under `lib/`. No dependency installation, submodule, RPC, environment
configuration, or network access is needed once the pinned compiler is installed.
Exact upstream commits, source archive hashes, and licences are recorded in
`lib/DEPENDENCIES.md`. Tests do not read or modify environment variables.

Tests cover metadata, one-time constructor allocation and event, factory
deployment, exact transfers, zero and self transfers, approvals and revocation,
finite and unlimited allowances, expected failures and rollback, absent admin
entry points, and Ether rejection. Four fuzz properties exercise transfers and
allowance boundaries with 1,024 cases each. A stateful invariant runs 256 sequences
of 64 operations across four holders and compares all balances and allowances
against an independent model, including failed operations and supply conservation.

## Deployment and operational responsibilities

The launch target is Ethereum mainnet (chain ID 1). Deploy the built
`src/FarmingSeason.sol:FarmingSeason` creation bytecode directly, with **no
constructor arguments and no attached ETH**. There are no linked libraries,
external constructor calls, initialization calls, or post-deployment settings.
The launch system creates its manifest separately; this project supplies the
contract and its build configuration.

During the IdentityMD factory launch, the factory is `msg.sender` and receives all
`10^27` smallest units. The token makes no launch allocations itself. The factory
handles the specified 10% swarm distribution, 80% liquidity allocation, and 10%
remainder according to the launch's economics. Every such token transfer is exact
and requires no exemption. A direct wallet deployment instead sends the whole
supply to that wallet. An intermediate deployment helper would receive the supply
itself, so the production launch should deploy this bytecode through its intended
factory.

The launch operator is responsible for checking the chain, compiled artifact,
constructor mint event, supply, and factory balance immediately after creation;
then checking the factory's distribution and verifying the source on the explorer.
Holders are responsible for key custody and approvals. Prefer exact spending
allowances and revoke unused ones; when changing an existing allowance, account
for the standard ERC-20 approval transaction-ordering race (revoke first, confirm,
then grant the new amount). There is no privileged recovery or maintenance role.

Local verification uses Foundry unit, fuzz, and stateful invariant tests plus
manual review against the supplied security reference. These checks do not replace
an independent security review. Slither and Mythril are not part of this project's
validation.
