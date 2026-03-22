#!/usr/bin/env bash
set -euo pipefail
export FOUNDRY_DISABLE_NIGHTLY_WARNING=1

# ═══════════════════════════════════════════════════════════════
#  RevStream — XRPL EVM Sidechain Demo
# ═══════════════════════════════════════════════════════════════
#
#  Deploys the SAME contracts to an XRPL EVM fork, demonstrating
#  multi-chain capability for the XRPL Commons sponsor.
#
#  Usage:
#    1. Start Anvil:  anvil --fork-url https://rpc.testnet.xrplevm.org --port 8546
#    2. Run demo:     bash script/demo-xrpl.sh
#
# ═══════════════════════════════════════════════════════════════

RPC="http://127.0.0.1:8546"

# Anvil default accounts (gas paid in XRP on XRPL EVM)
DEPLOYER_PK="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
SELLER_PK="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
INVESTOR_PK="0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"
CUSTOMER_PK="0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6"

DEPLOYER="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
SELLER="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
INVESTOR="0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
CUSTOMER="0x90F79bf6EB2c4f870365E785982E1f101E93b906"

# Helper: deploy contract and extract address
deploy_contract() {
  local output
  output=$(forge create "$1" --private-key "$2" --rpc-url "$RPC" --broadcast 2>&1)
  echo "$output" | grep -i "deployed to" | grep -oE '0x[0-9a-fA-F]{40}' | head -1
}

# Helper: parse cast call output — strips " [sci notation]" suffix
parse_uint() {
  echo "$1" | sed 's/ \[.*\]//g' | tr -d '[:space:]'
}

echo "═══════════════════════════════════════════════════════════"
echo "  RevStream — XRPL EVM Sidechain Demo"
echo "  Network: XRPL EVM Sidechain (Anvil fork)"
echo "  Gas token: XRP"
echo "═══════════════════════════════════════════════════════════"
echo ""

# ── Step 1: Deploy MockUSDC (no real USDC on XRPL EVM testnet) ──
echo "[1] Deploying MockUSDC (USDC-on-XRPL) stablecoin..."

USDC=$(deploy_contract "src/MockUSDC.sol:MockUSDC" "$DEPLOYER_PK")

echo "    MockUSDC deployed at: $USDC"

# Mint USDC to investor and customer
cast send "$USDC" "mint(address,uint256)" "$INVESTOR" 500000000000 \
  --private-key "$DEPLOYER_PK" --rpc-url "$RPC" > /dev/null 2>&1
cast send "$USDC" "mint(address,uint256)" "$CUSTOMER" 500000000000 \
  --private-key "$DEPLOYER_PK" --rpc-url "$RPC" > /dev/null 2>&1

RAW=$(cast call "$USDC" "balanceOf(address)(uint256)" "$INVESTOR" --rpc-url "$RPC" 2>/dev/null)
INV_BAL=$(parse_uint "$RAW")
RAW=$(cast call "$USDC" "balanceOf(address)(uint256)" "$CUSTOMER" --rpc-url "$RPC" 2>/dev/null)
CUST_BAL=$(parse_uint "$RAW")
echo "    Investor USDC: $((INV_BAL / 1000000))"
echo "    Customer USDC: $((CUST_BAL / 1000000))"
echo ""

# ── Step 2: Deploy AuctionFactory ─────────────────────────────
echo "[2] Deploying AuctionFactory on XRPL EVM..."

FACTORY=$(deploy_contract "src/AuctionFactory.sol:AuctionFactory" "$DEPLOYER_PK")

echo "    Factory deployed at: $FACTORY"
echo ""

# ── Step 3: Create auction for myshop.eth ─────────────────────
echo "[3] Creating auction: myshop.eth — XRPL payment revenue..."
echo "    Seller:        $SELLER"
echo "    Description:   Q2 2026 XRPL payment processing revenue"
echo "    Total tokens:  1,000,000 REV"
echo "    Duration:      1 day"

cast send "$FACTORY" \
  "createAuction(string,string,address,uint256,uint256)" \
  "myshop.eth" \
  "Q2 2026 XRPL payment processing revenue — settled on XRPL EVM Sidechain" \
  "$USDC" \
  1000000000000000000000000 \
  86400 \
  --private-key "$SELLER_PK" --rpc-url "$RPC" > /dev/null 2>&1

# Read auction to get RevToken address (field 4 from auctions mapping)
REV_TOKEN=$(cast call "$FACTORY" \
  "auctions(uint256)(string,string,address,address,address,uint256,uint256,uint256,address,bool)" 0 \
  --rpc-url "$RPC" 2>/dev/null | sed -n '4p' | tr -d '[:space:]')

echo "    Auction ID:    0"
echo "    RevToken at:   $REV_TOKEN"
echo ""

# ── Step 4: Investor bids (gas in XRP!) ───────────────────────
BID_AMOUNT=50000000000  # 50,000 USDC

echo "[4] Investor placing bid of 50,000 USDC (gas paid in XRP)..."
echo "    Investor:      $INVESTOR"

cast send "$USDC" "approve(address,uint256)(bool)" "$FACTORY" "$BID_AMOUNT" \
  --private-key "$INVESTOR_PK" --rpc-url "$RPC" > /dev/null 2>&1

cast send "$FACTORY" "bid(uint256,uint256)" 0 "$BID_AMOUNT" \
  --private-key "$INVESTOR_PK" --rpc-url "$RPC" > /dev/null 2>&1

echo "    Highest bid:   50,000 USDC"
echo "    Bidder:        $INVESTOR"
echo ""

# ── Step 5: Fast-forward & finalize ───────────────────────────
echo "[5] Fast-forwarding past auction deadline..."

cast rpc evm_increaseTime 86401 --rpc-url "$RPC" > /dev/null 2>&1
cast rpc evm_mine --rpc-url "$RPC" > /dev/null 2>&1

cast send "$FACTORY" "finalize(uint256)" 0 \
  --private-key "$SELLER_PK" --rpc-url "$RPC" > /dev/null 2>&1

RAW=$(cast call "$USDC" "balanceOf(address)(uint256)" "$SELLER" --rpc-url "$RPC" 2>/dev/null)
SELLER_BAL=$(parse_uint "$RAW")
RAW=$(cast call "$REV_TOKEN" "balanceOf(address)(uint256)" "$INVESTOR" --rpc-url "$RPC" 2>/dev/null)
INV_TOKENS=$(parse_uint "$RAW")

echo "    Auction finalized!"
echo "    Seller received:      $((SELLER_BAL / 1000000)) USDC"
echo "    Investor RevTokens:   $((INV_TOKENS / 1000000000000000000)) REV"
echo ""

# ── Step 6: Simulate XRPL merchant revenue ────────────────────
REVENUE=10000000000  # 10,000 USDC

echo "[6] Simulating XRPL merchant revenue: 10,000 USDC..."
echo "    Customer:      $CUSTOMER"

cast send "$USDC" "approve(address,uint256)(bool)" "$REV_TOKEN" "$REVENUE" \
  --private-key "$CUSTOMER_PK" --rpc-url "$RPC" > /dev/null 2>&1

cast send "$REV_TOKEN" "depositRevenue(uint256)" "$REVENUE" \
  --private-key "$CUSTOMER_PK" --rpc-url "$RPC" > /dev/null 2>&1

RAW=$(cast call "$REV_TOKEN" "epochRevenue(uint256)(uint256)" 0 --rpc-url "$RPC" 2>/dev/null)
EPOCH_REV=$(parse_uint "$RAW")
echo "    Revenue deposited for epoch 0"
echo "    Epoch revenue:  $((EPOCH_REV / 1000000)) USDC"
echo ""

# ── Step 7: Investor claims revenue share ─────────────────────
RAW=$(cast call "$REV_TOKEN" "claimable(uint256,address)(uint256)" 0 "$INVESTOR" --rpc-url "$RPC" 2>/dev/null)
CLAIMABLE=$(parse_uint "$RAW")

echo "[7] Investor claiming revenue share..."
echo "    Claimable:     $((CLAIMABLE / 1000000)) USDC"

RAW=$(cast call "$USDC" "balanceOf(address)(uint256)" "$INVESTOR" --rpc-url "$RPC" 2>/dev/null)
BAL_BEFORE=$(parse_uint "$RAW")

cast send "$REV_TOKEN" "claim(uint256)" 0 \
  --private-key "$INVESTOR_PK" --rpc-url "$RPC" > /dev/null 2>&1

RAW=$(cast call "$USDC" "balanceOf(address)(uint256)" "$INVESTOR" --rpc-url "$RPC" 2>/dev/null)
BAL_AFTER=$(parse_uint "$RAW")
CLAIMED=$(( (BAL_AFTER - BAL_BEFORE) / 1000000 ))

echo "    Claimed!       $CLAIMED USDC received"
echo ""

echo "═══════════════════════════════════════════════════════════"
echo "  ✅ XRPL EVM RevStream demo complete!"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "  Summary:"
echo "  - Same contracts deployed on XRPL EVM Sidechain"
echo "  - Gas paid in XRP (native XRPL EVM token)"
echo "  - myshop.eth auctioned Q2 2026 XRPL payment revenue"
echo "  - Investor won auction for 50,000 USDC"
echo "  - 10,000 USDC revenue deposited"
echo "  - Investor claimed 10,000 USDC (100% share)"
echo "  - ENS identity works cross-chain"
echo ""
echo "  XRPL Commons alignment:"
echo "  - Native deployment on XRPL EVM Sidechain"
echo "  - XRP as gas token, stablecoins for settlement"
echo "  - Bridges (Axelar/IBC) enable XRPL <> EVM revenue flows"
echo "═══════════════════════════════════════════════════════════"
