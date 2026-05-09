# SynapticChain Core

Core blockchain infrastructure for SynapticChain — contracts, compiler artifacts, and deployed applications.

## What's Here

| Directory | Contents |
|---|---|
| `contracts/dex/` | 6 DEX contracts in SynLang (.syn) — Factory, Router, Pool, OrderBook, PriceOracle, FeeCollector |
| `contracts/dapps/` | 5 compiled dApp contracts (.plan) — AMM DEX, Lending, Perpetuals, Prediction Market, NFT Marketplace |
| `web4-academy/` | Web4 Academy v2 — educational site with Staking + NFT sections |
| `token-launcher/` | SynapticLaunch frontend — token deployment UI |
| `chrome-extension/` | Browser extension source (Manifest V3, wallet injection, key recovery) |
| `contracts-page/` | DEX frontend contracts page |

## Contract Architecture

**DEX Contracts (Original):**
- `Factory.syn` — Pool creation and registry
- `Router.syn` — Swap routing and liquidity management
- `Pool.syn` — AMM pool logic (constant product)
- `OrderBook.syn` — Limit order matching engine
- `PriceOracle.syn` — On-chain price feeds
- `FeeCollector.syn` — Fee distribution and treasury

**dApp Contracts (Compiled):**
| Contract | Functions | State Slots | Plan Size |
|---|---|---|---|
| AMM DEX v4 | 24 | 13 | 131KB |
| Lending Protocol v2 | 36 | 17 | 154KB |
| Perpetuals v1 | 38 | 26 | 212KB |
| Prediction Market v1 | 26 | 20 | 133KB |
| NFT Marketplace v1 | 39 | 29 | 135KB |

## Compiler Note

SynLang uses `contract Name { state ... }` syntax. The original architecture specs used `#[state] struct` notation — these have been translated to actual SynLang syntax and compiled successfully.

## Git

Branch: `main` (protected)
Review required for all PRs.
