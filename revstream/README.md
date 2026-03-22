# RevStream 💸

**Revenue-backed, stablecoin-denominated future cashflow marketplace.**

Built for the [BSA-EPFL Stablecoins & Payments Hackathon](https://hackathon.bsaepfl.ch) (DoraHacks).

---

## 🧠 Concept

Protocols and merchants with **recurring stablecoin revenue** (fees, subscriptions, payment processing) can **sell a slice of their future revenue today** — receiving upfront capital without diluting equity.

Investors buy tokenized claims via on-chain auctions and receive **RevTokens** (ERC-20), which entitle them to a **pro-rata share of future stablecoin inflows**.

```
┌─────────────┐     auction      ┌──────────────┐     revenue     ┌──────────────┐
│  Seller      │ ──────────────▸ │ AuctionFactory│ ◂──────────── │  Customers    │
│ (myshop.eth) │   ◂── USDC ──  │              │                │  (pay USDC)   │
└─────────────┘   upfront capital└──────┬───────┘                └──────────────┘
                                        │ mints RevTokens                │
                                        ▾                                │
                                 ┌──────────────┐         depositRevenue │
                                 │   RevToken    │ ◂─────────────────────┘
                                 │  (ERC-20)     │
                                 └──────┬───────┘
                                        │ claim()
                                        ▾
                                 ┌──────────────┐
                                 │   Investors   │  ← receive pro-rata USDC
                                 └──────────────┘
```

---

## 🏗️ Architecture

### Contracts

| Contract | Description |
|---|---|
| **`AuctionFactory.sol`** | Creates revenue auctions tied to ENS names. Manages bidding (highest-bid-wins) and finalizes auctions by minting RevTokens. |
| **`RevToken.sol`** | ERC-20 representing future revenue shares. Handles epoch-based revenue deposits and pro-rata claims. |

### ENS Integration 🔗

ENS is a **first-class identity layer** in RevStream, not just an address resolver:

- **Seller identity**: Each auction is tied to an ENS name (e.g., `myshop.eth`), providing verifiable, human-readable identity for the revenue source.
- **On-chain indexing**: Auctions are indexed by ENS name hash (`keccak256(ensName)`), enabling on-chain lookups via `getAuctionsByEns("myshop.eth")`.
- **Token naming**: RevTokens automatically derive their name/symbol from the ENS name (e.g., `RevStream: myshop.eth` / `REV-myshop.`).
- **Trust anchor**: Investors can verify the ENS name resolves to the seller's address, establishing a trust chain between the auction and a real protocol/merchant identity.

**Future ENS extensions** (post-hackathon):
- On-chain ENS resolution to verify seller ownership during `createAuction`.
- ENS text records for revenue stream metadata (payout chains, stablecoin preferences, revenue descriptions).
- ENS subnames for individual revenue streams (e.g., `q2-2026.myshop.eth`).

---

## 🌊 AlphaTON Capital: TON-Ready Architecture

RevStream is **EVM-first, TON-ready**. The architecture is designed to extend to the TON ecosystem:

### Why TON + RevStream?

- **Telegram mini-apps** generate stablecoin revenue (USDT-on-TON, Toncoin) from millions of users.
- **AlphaTON-backed projects** need non-dilutive financing — RevStream lets them sell future revenue claims without giving up equity.
- **USDT on TON** is one of the largest stablecoin deployments — perfect for revenue-backed instruments.

### Planned TON Integration

```
┌─────────────────────┐          ┌─────────────────────┐
│   EVM (Base/Ethereum)│          │        TON           │
│                     │          │                     │
│  AuctionFactory     │          │  TON Revenue Router  │
│  RevToken           │◂────────▸│  (Accepts USDT-TON)  │
│                     │  bridge  │                     │
│  Revenue claims     │          │  Telegram mini-apps  │
│  settled in USDC    │          │  TON DeFi protocols  │
└─────────────────────┘          └─────────────────────┘
```

1. **TON Revenue Router**: A TON contract that collects USDT-on-TON / Toncoin revenue from mini-apps.
2. **Cross-chain bridge**: Revenue is bridged to EVM (via LayerZero, Wormhole, or TON Bridge) and deposited into the RevToken contract.
3. **Unified claim model**: RevToken holders claim revenue regardless of which chain generated it.

This makes AlphaTON portfolio companies — TON-native projects with real stablecoin revenue — ideal sellers on RevStream.

---

## 🚀 Quick Start

### Prerequisites

- [Foundry](https://getfoundry.sh) installed
- An Ethereum RPC URL (Alchemy, Infura, etc.) for fork testing

### Build & Test

```bash
cd revstream
forge build
forge test -vvv
```

### Fork Demo (Mainnet)

The demo runs the full lifecycle on a mainnet fork using **real USDC**:

```bash
# Terminal 1: Start Anvil forked from Ethereum mainnet
anvil --fork-url https://eth-mainnet.g.alchemy.com/v2/YOUR_KEY

# Terminal 2: Run the demo
cd revstream
bash script/demo.sh
```

**Demo flow:**
1. Seeds demo accounts with USDC from a mainnet whale
2. Deploys `AuctionFactory`
3. Creates auction for `myshop.eth` — "Q2 2026 stablecoin revenue"
4. Investor bids 50,000 USDC and wins
5. Auction finalized → seller receives USDC, investor gets 1M RevTokens
6. Customer deposits 10,000 USDC as simulated revenue
7. Investor claims 10,000 USDC (100% pro-rata share)

All steps produce clear console logs so judges can follow along.

---

## 📂 Project Structure

```
revstream/
├── src/
│   ├── AuctionFactory.sol   # Auction creation, bidding, finalization
│   └── RevToken.sol         # Revenue share token + distribution
├── test/
│   ├── RevStream.t.sol      # 12 unit tests covering full lifecycle
│   └── Demo.t.sol           # Fork-based demo (alternative: forge test --fork-url)
├── script/
│   ├── demo.sh              # End-to-end fork demo (recommended)
│   └── Demo.s.sol           # Foundry script (reference)
└── foundry.toml             # Foundry configuration
```

---

## 🧪 Test Coverage

| Test | What it covers |
|---|---|
| `test_createAuction` | Auction creation with ENS metadata |
| `test_createAuction_emptyEns_reverts` | Input validation |
| `test_getAuctionsByEns` | ENS-based auction lookup |
| `test_bid` | Placing a bid with stablecoin |
| `test_bid_outbid_refunds` | Automatic refund on outbid |
| `test_bid_tooLow_reverts` | Bid validation |
| `test_bid_afterDeadline_reverts` | Deadline enforcement |
| `test_finalize` | Auction settlement + RevToken minting |
| `test_finalize_tooEarly_reverts` | Timing enforcement |
| `test_depositAndClaim` | Revenue deposit + claim lifecycle |
| `test_doubleClaim_reverts` | Double-claim prevention |
| `test_multipleHolders_proRata` | Pro-rata distribution across holders |

---

## 🔮 Roadmap

- [ ] **ENS on-chain resolution** — Verify seller owns the ENS name at auction creation
- [ ] **ENS text records** — Store revenue metadata in ENS records
- [ ] **TON Revenue Router** — Accept USDT-on-TON from Telegram mini-apps
- [ ] **Multi-epoch streaming** — Continuous revenue distribution (like Sablier)
- [ ] **Dutch auction model** — Price discovery via descending-price auctions
- [ ] **Secondary market** — RevToken trading on DEXs (tokens are already ERC-20)
- [ ] **Credit scoring** — On-chain revenue history as creditworthiness signal

---

## 🙏 Acknowledgments

- **ENS** — Identity layer for seller verification
- **AlphaTON Capital** — TON ecosystem alignment and future deployment target
- **BSA-EPFL** — Hackathon organization

---

*Built with ❤️ for the BSA-EPFL Stablecoins & Payments Hackathon*
