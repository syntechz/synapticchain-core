# SynapticChain Core

Smart contract suite for the SynapticChain blockchain.

## Contracts

### DEX (`contracts/dex/`)
- `Factory.syn` — Pool factory for AMM
- `Router.syn` — Trade routing
- `Pool.syn` — Liquidity pool
- `OrderBook.syn` — Limit order matching
- `PriceOracle.syn` — Price feed aggregator
- `FeeCollector.syn` — Fee distribution

### Lending (`contracts/lending/`)
- `lending_protocol.syn` — Collateralized lending

### Perpetuals (`contracts/perps/`)
- `perpetuals.syn` — Perpetual futures exchange

### Prediction (`contracts/prediction/`)
- `prediction_market.syn` — Binary outcome markets

### NFT (`contracts/nft/`)
- `nft_marketplace.syn` — NFT trading + royalties

## Deployment

See `deploy_dex.sh` for testnet deployment sequence.
