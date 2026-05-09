#!/usr/bash
# SynapticChain DEX Testnet Deployment Script
# Run this on the synapticchain VPS where synlang and synaptic-node are installed
#
# Prerequisites:
#   - synlang compiler in PATH
#   - synaptic-node running and connected to Charlie testnet
#   - Wallet with test SYN for gas fees
#
# IMPORTANT: Apply P0 fixes from Contract Review before running this script.
#   See: SynapticChain_DEX_Contract_Review.md

set -euo pipefail

# Configuration
CHAIN_ID="charlie-testnet"
CONTRACTS_DIR="/opt/synapticchain/contracts/dex"
BUILD_DIR="/opt/synapticchain/build/dex"
DEPLOY_LOG="/opt/synapticchain/logs/dex_deploy.log"
TESTNET_RPC="http://localhost:8545"  # Adjust to your testnet RPC endpoint

# Token addresses (testnet — update with actual deployed addresses)
# These are placeholder test tokens. Replace after deploying SYN + wrapped tokens.
SYN_TOKEN="0xTEST_SYN_PLACEHOLDER"
WETH_TOKEN="0xTEST_WETH_PLACEHOLDER"
TUSDT="0xTEST_USDT_PLACEHOLDER"
TUSDC="0xTEST_USDC_PLACEHOLDER"
TBTC="0xTEST_BTC_PLACEHOLDER"
TESG="0xTEST_ESG_PLACEHOLDER"

# Gas settings
GAS_LIMIT="5000000"
GAS_PRICE="1"

echo "=========================================="
echo "SynapticChain DEX Testnet Deployment"
echo "=========================================="
echo "Chain:      $CHAIN_ID"
echo "Contracts:  $CONTRACTS_DIR"
echo "Build:      $BUILD_DIR"
echo "RPC:        $TESTNET_RPC"
echo "Date:       $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

# Create directories
mkdir -p "$BUILD_DIR"
mkdir -p "$(dirname "$DEPLOY_LOG")"

# --- Check prerequisites ---
echo "[1/8] Checking prerequisites..."

if ! command -v synlang &> /dev/null; then
    echo "ERROR: synlang compiler not found in PATH"
    echo "Install or source the synapticchain environment first:"
    echo "  source /opt/synapticchain/env.sh"
    exit 1
fi

if ! command -v synaptic-node &> /dev/null; then
    echo "ERROR: synaptic-node not found in PATH"
    exit 1
fi

# Check node is running
if ! curl -s "$TESTNET_RPC" -X POST -H "Content-Type: application/json" \
    -d '{"jsonrpc":"2.0","method":"synaptic_chainId","id":1}' | grep -q "$CHAIN_ID"; then
    echo "WARNING: Could not verify testnet connection at $TESTNET_RPC"
    echo "Ensure synaptic-node is running on the testnet before deploying."
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "✓ Prerequisites OK"

# --- Compile contracts ---
echo ""
echo "[2/8] Compiling contracts..."

CONTRACTS=(
    "Factory"
    "Pool"
    "Router"
    "OrderBook"
    "PriceOracle"
    "FeeCollector"
)

COMPILE_STATUS=()
for contract in "${CONTRACTS[@]}"; do
    src="$CONTRACTS_DIR/${contract}.syn"
    out="$BUILD_DIR/${contract}.wasm"
    
    if [[ ! -f "$src" ]]; then
        echo "ERROR: Source file not found: $src"
        COMPILE_STATUS+=("FAIL: $contract — file missing")
        continue
    fi
    
    echo "  Compiling ${contract}.syn..."
    
    if synlang compile "$src" -o "$out" >> "$DEPLOY_LOG" 2>&1; then
        echo "    ✓ PASS — ${contract}.wasm ($(stat -c%s "$out" 2>/dev/null || echo '?') bytes)"
        COMPILE_STATUS+=("PASS: $contract")
    else
        echo "    ✗ FAIL — ${contract}.syn"
        echo "    See $DEPLOY_LOG for compiler output"
        COMPILE_STATUS+=("FAIL: $contract — compile error")
    fi
done

echo ""
echo "--- Compile Summary ---"
for status in "${COMPILE_STATUS[@]}"; do
    echo "  $status"
done

# Abort if any compile failed
if printf '%s\n' "${COMPILE_STATUS[@]}" | grep -q "FAIL"; then
    echo ""
    echo "ERROR: One or more contracts failed to compile."
    echo "Fix the issues and re-run this script."
    echo "Review: SynapticChain_DEX_Contract_Review.md"
    exit 1
fi

echo ""
echo "✓ All contracts compiled successfully"

# --- Deploy contracts ---
echo ""
echo "[3/8] Deploying contracts to testnet..."

# Deploy Factory first (no dependencies)
echo "  Deploying Factory..."
FACTORY_ADDR=$(synaptic-node deploy \
    --wasm "$BUILD_DIR/Factory.wasm" \
    --rpc "$TESTNET_RPC" \
    --gas-limit "$GAS_LIMIT" \
    --gas-price "$GAS_PRICE" \
    --args "" \
    2>> "$DEPLOY_LOG" | tail -1)

if [[ -z "$FACTORY_ADDR" || "$FACTORY_ADDR" == "0x"*"0" ]]; then
    echo "ERROR: Factory deployment failed"
    exit 1
fi
echo "    ✓ Factory at $FACTORY_ADDR"

# Deploy FeeCollector (depends on Factory)
echo "  Deploying FeeCollector..."
FEE_COLLECTOR_ADDR=$(synaptic-node deploy \
    --wasm "$BUILD_DIR/FeeCollector.wasm" \
    --rpc "$TESTNET_RPC" \
    --gas-limit "$GAS_LIMIT" \
    --gas-price "$GAS_PRICE" \
    --args "${FACTORY_ADDR},${SYN_TOKEN}" \
    2>> "$DEPLOY_LOG" | tail -1)
echo "    ✓ FeeCollector at $FEE_COLLECTOR_ADDR"

# Deploy PriceOracle (depends on Factory)
echo "  Deploying PriceOracle..."
ORACLE_ADDR=$(synaptic-node deploy \
    --wasm "$BUILD_DIR/PriceOracle.wasm" \
    --rpc "$TESTNET_RPC" \
    --gas-limit "$GAS_LIMIT" \
    --gas-price "$GAS_PRICE" \
    --args "$FACTORY_ADDR" \
    2>> "$DEPLOY_LOG" | tail -1)
echo "    ✓ PriceOracle at $ORACLE_ADDR"

# Deploy Pool (template — each pool is a new instance)
# Note: Pool is deployed via Factory.create_pool, not directly
echo "  Pool contract compiled (deployed per-pair via Factory)"

# Deploy Router (depends on Factory + WETH)
echo "  Deploying Router..."
ROUTER_ADDR=$(synaptic-node deploy \
    --wasm "$BUILD_DIR/Router.wasm" \
    --rpc "$TESTNET_RPC" \
    --gas-limit "$GAS_LIMIT" \
    --gas-price "$GAS_PRICE" \
    --args "${FACTORY_ADDR},${WETH_TOKEN}" \
    2>> "$DEPLOY_LOG" | tail -1)
echo "    ✓ Router at $ROUTER_ADDR"

# Deploy OrderBook (depends on Factory)
echo "  Deploying OrderBook..."
ORDERBOOK_ADDR=$(synaptic-node deploy \
    --wasm "$BUILD_DIR/OrderBook.wasm" \
    --rpc "$TESTNET_RPC" \
    --gas-limit "$GAS_LIMIT" \
    --gas-price "$GAS_PRICE" \
    --args "$FACTORY_ADDR" \
    2>> "$DEPLOY_LOG" | tail -1)
echo "    ✓ OrderBook at $ORDERBOOK_ADDR"

echo ""
echo "✓ All contracts deployed"

# --- Create initial pools ---
echo ""
echo "[4/8] Creating initial liquidity pools..."

# Pool pairs to create
POOL_PAIRS=(
    "${SYN_TOKEN},${TUSDT},30"
    "${SYN_TOKEN},${TBTC},30"
    "${TUSDT},${TUSDC},5"
    "${SYN_TOKEN},${TESG},30"
)

POOL_ADDRESSES=()
for pair in "${POOL_PAIRS[@]}"; do
    IFS=',' read -r token0 token1 fee <<< "$pair"
    
    echo "  Creating pool: $(basename "$token0") / $(basename "$token1") @ ${fee}bps..."
    
    POOL_ADDR=$(synaptic-node call \
        --contract "$FACTORY_ADDR" \
        --method "create_pool" \
        --args "${token0},${token1},${fee}" \
        --rpc "$TESTNET_RPC" \
        --gas-limit "$GAS_LIMIT" \
        --gas-price "$GAS_PRICE" \
        2>> "$DEPLOY_LOG" | tail -1)
    
    if [[ -n "$POOL_ADDR" && "$POOL_ADDR" != "0x"*"0" ]]; then
        echo "    ✓ Pool at $POOL_ADDR"
        POOL_ADDRESSES+=("$POOL_ADDR")
    else
        echo "    ✗ Pool creation failed (non-fatal, can retry later)"
    fi
done

echo ""
echo "✓ Pools created: ${#POOL_ADDRESSES[@]}"

# --- Seed initial liquidity (optional) ---
echo ""
echo "[5/8] Seeding initial liquidity..."

# This requires test tokens in the deployer wallet
# Uncomment and configure when test tokens are funded

echo "  (Skipped — ensure deployer wallet has test tokens before adding liquidity)"
echo "  Use the Router.add_liquidity method after funding:"
echo "    synaptic-node call --contract $ROUTER_ADDR --method add_liquidity ..."

# --- Update FeeCollector with deployed pools ---
echo ""
echo "[6/8] Registering pools with FeeCollector..."

for pool_addr in "${POOL_ADDRESSES[@]}"; do
    synaptic-node call \
        --contract "$FEE_COLLECTOR_ADDR" \
        --method "collect_fees" \
        --args "$pool_addr" \
        --rpc "$TESTNET_RPC" \
        --gas-limit "$GAS_LIMIT" \
        --gas-price "$GAS_PRICE" \
        >> "$DEPLOY_LOG" 2>&1 || true
done

echo "✓ Pools registered"

# --- Output frontend config ---
echo ""
echo "[7/8] Generating frontend configuration..."

CONFIG_FILE="$BUILD_DIR/dex_config.json"

cat > "$CONFIG_FILE" <<EOF
{
  "network": {
    "chainId": "$CHAIN_ID",
    "rpcUrl": "$TESTNET_RPC",
    "name": "SynapticChain Charlie Testnet"
  },
  "contracts": {
    "Factory": "$FACTORY_ADDR",
    "Router": "$ROUTER_ADDR",
    "OrderBook": "$ORDERBOOK_ADDR",
    "PriceOracle": "$ORACLE_ADDR",
    "FeeCollector": "$FEE_COLLECTOR_ADDR"
  },
  "tokens": {
    "SYN": "$SYN_TOKEN",
    "WETH": "$WETH_TOKEN",
    "tUSDT": "$TUSDT",
    "tUSDC": "$TUSDC",
    "tBTC": "$TBTC",
    "tESG": "$TESG"
  },
  "pools": [
$(printf '    "%s",\n' "${POOL_ADDRESSES[@]}" | sed '$ s/,$//')
  ],
  "deployment": {
    "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
    "version": "1.0.0-testnet",
    "compiler": "synlang",
    "log": "$DEPLOY_LOG"
  }
}
EOF

echo "✓ Config written to $CONFIG_FILE"

# --- Print summary ---
echo ""
echo "=========================================="
echo "DEPLOYMENT COMPLETE"
echo "=========================================="
echo ""
echo "Contract Addresses:"
echo "  Factory:       $FACTORY_ADDR"
echo "  Router:        $ROUTER_ADDR"
echo "  OrderBook:     $ORDERBOOK_ADDR"
echo "  PriceOracle:   $ORACLE_ADDR"
echo "  FeeCollector:  $FEE_COLLECTOR_ADDR"
echo ""
echo "Pools Created: ${#POOL_ADDRESSES[@]}"
for addr in "${POOL_ADDRESSES[@]}"; do
    echo "  - $addr"
done
echo ""
echo "Frontend Config: $CONFIG_FILE"
echo "Deploy Log:      $DEPLOY_LOG"
echo ""
echo "=========================================="
echo "NEXT STEPS"
echo "=========================================="
echo ""
echo "1. Fund the deployer wallet with test SYN for gas"
echo "2. Fund test token contracts (tUSDT, tBTC, etc.) to the deployer"
echo "3. Add initial liquidity via Router.add_liquidity()"
echo "4. Copy dex_config.json into the frontend src/config/ directory"
echo "5. Start the DEX frontend and connect to $TESTNET_RPC"
echo ""
echo "To verify contracts are live:"
echo "  curl $TESTNET_RPC -X POST -d '{\"jsonrpc\":\"2.0\",\"method\":\"synaptic_getCode\",\"params\":[\"$FACTORY_ADDR\"],\"id\":1}'"
echo ""
echo "=========================================="

exit 0
