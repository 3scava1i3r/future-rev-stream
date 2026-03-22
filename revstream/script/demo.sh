#!/usr/bin/env bash
set -euo pipefail

# ═══════════════════════════════════════════════════════════════
#  RevStream — End-to-End Fork Demo
# ═══════════════════════════════════════════════════════════════
#
#  Usage:
#    1. Start Anvil:  anvil --fork-url https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY
#    2. Run demo:     bash script/demo.sh
#
# ═══════════════════════════════════════════════════════════════

RPC="http://127.0.0.1:8545"

# Mainnet USDC
USDC="0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
# USDC whale (Circle)
WHALE="0x55FE002aefF02F77364de339a1292923A15844B8"

# Anvil default accounts
SELLER_PK="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
INVESTOR_PK="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
CUSTOMER_PK="0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"

SELLER="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
INVESTOR="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
CUSTOMER="0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"

echo "======================================================="
echo "  RevStream — Future Revenue Marketplace Demo"
echo "======================================================="
echo ""

# ── Step 0: Seed USDC from whale ──────────────────────────────
echo "[0] Seeding demo accounts with USDC from whale..."

cast rpc anvil_impersonateAccount "$WHALE" --rpc-url "$RPC" > /dev/null

cast send "$USDC" "transfer(address,uint256)(bool)" "$INVESTOR" 500000000000 \
  --from "$WHALE" --unlocked --rpc-url "$RPC" > /dev/null

cast send "$USDC" "transfer(address,uint256)(bool)" "$CUSTOMER" 500000000000 \
  --from "$WHALE" --unlocked --rpc-url "$RPC" > /dev/null

INV_BAL=$(cast call "$USDC" "balanceOf(address)(uint256)" "$INVESTOR" --rpc-url "$RPC")
CUST_BAL=$(cast call "$USDC" "balanceOf(address)(uint256)" "$CUSTOMER" --rpc-url "$RPC")
echo "    Investor USDC: $(echo "$INV_BAL / 1000000" | bc)"
echo "    Customer USDC: $(echo "$CUST_BAL / 1000000" | bc)"
echo ""

# ── Step 1: Deploy AuctionFactory ─────────────────────────────
echo "[1] Deploying AuctionFactory..."

FACTORY=$(forge create src/AuctionFactory.sol:AuctionFactory \
  --private-key "$SELLER_PK" --rpc-url "$RPC" --json | jq -r '.deployedTo')

echo "    Factory deployed at: $FACTORY"
echo ""

# ── Step 2: Create auction for myshop.eth ─────────────────────
echo "[2] Creating auction for myshop.eth..."
echo "    Seller:        $SELLER"
echo "    Description:   Q2 2026 stablecoin revenue"
echo "    Total tokens:  1,000,000 REV"
echo "    Duration:      1 day"

AUCTION_RESULT=$(cast send "$FACTORY" \
  "createAuction(string,string,address,uint256,uint256)(uint256)" \
  "myshop.eth" \
  "Q2 2026 stablecoin revenue from myshop.eth payment processing" \
  "$USDC" \
  1000000000000000000000000 \
  86400 \
  --private-key "$SELLER_PK" --rpc-url "$RPC" --json)

# Read auction to get RevToken address
AUCTION_DATA=$(cast call "$FACTORY" "getAuction(uint256)" 0 --rpc-url "$RPC")
# RevToken is the 4th field (offset 0x60) — extract it
REV_TOKEN=$(cast abi-decode "getAuction()(string,string,address,address,address,uint256,uint256,uint256,address,bool)" "$AUCTION_DATA" | sed -n '4p')

echo "    Auction ID:    0"
echo "    RevToken at:   $REV_TOKEN"
echo ""

# ── Step 3: Investor places a bid ─────────────────────────────
BID_AMOUNT=50000000000  # 50,000 USDC

echo "[3] Investor placing bid of 50,000 USDC..."
echo "    Investor:      $INVESTOR"

cast send "$USDC" "approve(address,uint256)(bool)" "$FACTORY" "$BID_AMOUNT" \
  --private-key "$INVESTOR_PK" --rpc-url "$RPC" > /dev/null

cast send "$FACTORY" "bid(uint256,uint256)" 0 "$BID_AMOUNT" \
  --private-key "$INVESTOR_PK" --rpc-url "$RPC" > /dev/null

echo "    Highest bid:   50000 USDC"
echo "    Bidder:        $INVESTOR"
echo ""

# ── Step 4: Fast-forward time & finalize ──────────────────────
echo "[4] Fast-forwarding past auction deadline..."

cast rpc evm_increaseTime 86401 --rpc-url "$RPC" > /dev/null
cast rpc evm_mine --rpc-url "$RPC" > /dev/null

cast send "$FACTORY" "finalize(uint256)" 0 \
  --private-key "$SELLER_PK" --rpc-url "$RPC" > /dev/null

SELLER_BAL=$(cast call "$USDC" "balanceOf(address)(uint256)" "$SELLER" --rpc-url "$RPC")
INV_TOKENS=$(cast call "$REV_TOKEN" "balanceOf(address)(uint256)" "$INVESTOR" --rpc-url "$RPC")

echo "    Auction finalized!"
echo "    Seller received:      $(echo "$SELLER_BAL / 1000000" | bc) USDC"
echo "    Investor RevTokens:   $(echo "$INV_TOKENS / 1000000000000000000" | bc) REV"
echo ""

# ── Step 5: Simulate revenue deposit ──────────────────────────
REVENUE=10000000000  # 10,000 USDC

echo "[5] Simulating revenue: customer pays 10,000 USDC..."
echo "    Customer:      $CUSTOMER"

cast send "$USDC" "approve(address,uint256)(bool)" "$REV_TOKEN" "$REVENUE" \
  --private-key "$CUSTOMER_PK" --rpc-url "$RPC" > /dev/null

cast send "$REV_TOKEN" "depositRevenue(uint256)" "$REVENUE" \
  --private-key "$CUSTOMER_PK" --rpc-url "$RPC" > /dev/null

EPOCH_REV=$(cast call "$REV_TOKEN" "epochRevenue(uint256)(uint256)" 0 --rpc-url "$RPC")
echo "    Revenue deposited for epoch 0"
echo "    Epoch revenue:  $(echo "$EPOCH_REV / 1000000" | bc) USDC"
echo ""

# ── Step 6: Investor claims revenue share ─────────────────────
CLAIMABLE=$(cast call "$REV_TOKEN" "claimable(uint256,address)(uint256)" 0 "$INVESTOR" --rpc-url "$RPC")

echo "[6] Investor claiming revenue share..."
echo "    Claimable:     $(echo "$CLAIMABLE / 1000000" | bc) USDC"

BAL_BEFORE=$(cast call "$USDC" "balanceOf(address)(uint256)" "$INVESTOR" --rpc-url "$RPC")

cast send "$REV_TOKEN" "claim(uint256)" 0 \
  --private-key "$INVESTOR_PK" --rpc-url "$RPC" > /dev/null

BAL_AFTER=$(cast call "$USDC" "balanceOf(address)(uint256)" "$INVESTOR" --rpc-url "$RPC")
CLAIMED=$(echo "($BAL_AFTER - $BAL_BEFORE) / 1000000" | bc)

echo "    Claimed!       $CLAIMED USDC received"
echo ""

echo "======================================================="
echo "  Demo complete! RevStream lifecycle demonstrated."
echo "======================================================="
echo ""
echo "  Summary:"
echo "  - myshop.eth auctioned Q2 2026 revenue"
echo "  - Investor won auction for 50,000 USDC"
echo "  - 10,000 USDC revenue deposited"
echo "  - Investor claimed 10,000 USDC (100% share)"
echo "  - ENS name tied to auction metadata on-chain"
echo "======================================================="
