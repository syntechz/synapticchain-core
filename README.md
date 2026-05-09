# SynapticChain Core

[![Blockchain](https://img.shields.io/badge/Blockchain-SynapticChain-00d4ff?style=flat-square)](https://synapticchain.xyz)
[![Contracts](https://img.shields.io/badge/Contracts-11%20compiled-success?style=flat-square)](./contracts)
[![Gateway](https://img.shields.io/badge/Gateway-v3%20live-brightgreen?style=flat-square)](https://api.synapticchain.xyz)
[![License](https://img.shields.io/badge/License-MIT-blue?style=flat-square)](./LICENSE)

> Core blockchain infrastructure for SynapticChain — contracts, compiler artifacts, deployed dApps, and the unified API gateway.

## What's Here

| Directory | Contents |
|---|---|
| `contracts/dex/` | 6 DEX contracts in SynLang (.syn) — Factory, Router, Pool, OrderBook, PriceOracle, FeeCollector |
| `contracts/dapps/` | 5 compiled dApp contracts (.plan) — AMM DEX, Lending, Perpetuals, Prediction Market, NFT Marketplace |
| `web4-academy/` | Web4 Academy v2 — educational site with Staking + NFT sections |
| `token-launcher/` | SynapticLaunch frontend — token deployment UI |
| `chrome-extension/` | Browser extension source (Manifest V3, wallet injection, key recovery) |
| `contracts-page/` | DEX frontend contracts page |
| `api-gateway/` | Node.js/Express + Redis unified API gateway — round-robin proxy to 18 validators |
| `docs-site/` | GitBook-style docs site for docs.synapticchain.xyz — 10 sections, dark theme |
| `flagship_domains/` | Ecosystem directory with custom domain links |

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

## Live Network

| Endpoint | URL |
|---|---|
| Main Explorer | https://explorer.synapticchain.com |
| Testnet Explorer | https://testnet-explorer.synapticchain.com |
| API Gateway | https://api.synapticchain.xyz |
| RPC | https://rpc.synapticchain.com |
| Docs | https://docs.synapticchain.xyz |

## API Gateway

The unified API gateway (`api-gateway/`) provides:
- Round-robin proxy across all 18 validator nodes (Alpha + Bravo)
- Redis hot-read cache (blocks, validators, metrics) — TTL 2-5s
- Rate limiting: 300 req/min per IP
- Health checks every 5s — dead nodes auto-removed
- 7 REST endpoints: `/health`, `/rest/blocks`, `/rest/validators`, `/rest/shards`, `/rest/network/stats`, `/rest/metrics`, `/rpc`
- Prometheus aggregation from `:3000/:9100`
- CORS enabled for all dApp origins

**Deploy:**
```bash
cd api-gateway
bash install.sh  # installs Redis, npm deps, starts with PM2
curl http://localhost:8080/health  # verify
```

## Docs Site

GitBook-style documentation at `docs.synapticchain.xyz`:
- 10 sections: Intro, Architecture, Quick Start, API Reference, Smart Contracts, SynapticLang v2, Web4 Identity, Validator Setup, Tutorials, Chrome Extension, Glossary
- Left sidebar nav, client-side search, dark Neural-Speed theme
- All 5 contract addresses + function signatures
- Code examples for wallet, RPC, contract deployment

## Compiler Note

SynLang uses `contract Name { state ... }` syntax. The original architecture specs used `#[state] struct` notation — these have been translated to actual SynLang syntax and compiled successfully.

## Ecosystem

| Property | URL | Status |
|---|---|---|
| synapticchain.com | https://synapticchain.com | Live |
| synswap.xyz | https://synswap.xyz | Live |
| synnft.xyz | https://synnft.xyz | Live |
| synmint.xyz | https://synmint.xyz | Live |
| synplay.xyz | https://synplay.xyz | Live |
| syntrade.xyz | https://syntrade.xyz | Live |
| synleaf.xyz | https://synleaf.xyz | Live |
| synscan.xyz | https://synscan.xyz | Live |

## Git

Branch: `main` (protected)  
Review required for all PRs.
