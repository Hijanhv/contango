# Programmable Money Hackathon (Arc × Circle) — The Winning Play

*Grounded in: the DeFi/Agentic track briefs, Circle's Arc strategy (StableFX/FX/treasury/capital-markets), the Arc `llms.txt` doc surface, a top-to-bottom read of 18 past-winner codebases, and two independent idea passes (main + Fable) reconciled.*

---

## The one insight that wins

**Every past winner built the payment-execution layer. Nobody built the alpha/strategy layer.**

- OmniAgentPay (1st), Arc Merchant (2nd), agent banks, escrow, storefronts — all *"how does money move safely."*
- Their actual code uses only **Developer-Controlled Wallets + x402**. Across all 18 repos: **zero** real use of App Kit **Swap**, **Bridge**, **CCTP**, **Gateway**, **StableFX**, or **Paymaster**. Only Solidity shipped: escrow / streaming / insurance.
- **No one built a quant DeFi product** — no FX engine, no derivatives, no risk-managed yield. That lane is empty **and it is exactly Circle's strategic priority** (StableFX, treasury, capital markets, 24/7 on-chain FX).

> They built **Stripe-for-agents** (moving money). You build the **derivative/FX layer** Circle's own roadmap needs next.

---

## FLAGSHIP — **Contango**
### "24/7 margined FX forwards for stablecoins — margin-and-code replace ISDA-and-credit-lines."

**One-liner:** Anyone (or any agent) can lock a future EURUSD exchange rate with **$50 instead of $1M**, 24/7, no bank and no ISDA — and a delta-neutral vault earns the carry. *("Contango" is the term for a forward curve trading above spot — naming the protocol after the structure it builds signals derivatives literacy to judges instantly.)*

**Track:** DeFi (primary) + Agentic Economy (the Hedger Agent is a real autonomous customer) → **one project, both tracks.**

### The gap it fills
Circle built **spot** FX (App Kit Swap now; StableFX for institutions). Nobody built the instrument every real FX use case needs: the **forward**. An importer paying a EUR invoice in 60 days, a SaaS with EURC revenue and USD payroll, an agent managing a multi-currency treasury — none need spot; they need to **lock a rate for a future date**. FX forwards are a **~$110T/yr** market, and in TradFi they're *credit* instruments (ISDA, bank credit lines, T+2, closed weekends, ~$1M min tickets) — so banks refuse SMEs or quote them 50–200bps. **That is the wedge, squarely inside Circle's FX/treasury/capital-markets priority.**

### The quant strategy (the star — her edge)
**1. Pricing — Covered Interest Parity (CIP).** Fair forward for EURUSD at tenor τ:

    F = S · (1 + r_USD·τ) / (1 + r_EUR·τ)

S = spot USDC/EURC mid; r_USD = SOFR, r_EUR = €STR (live published fixings; a rates keeper posts real Fed/ECB data on-chain). USD>EUR rates ⇒ positive forward points. Engine quotes bid/ask around CIP fair value.

**2. Market making — inventory-skewed quoting (Avellaneda–Stoikov-lite).** Protocol desk is counterparty to all forwards. Quote mid = F − k·q (q = net forward EUR delta, k = risk aversion): skew/widen when the book is one-sided, tighten when balanced. **This is Catenaccio's loop, reused.**

**3. Carry Vault — delta-neutral FX desk economics on-chain (ERC-4626).** The desk's balance sheet. Every forward written is immediately **delta-hedged with a spot trade on App Kit Swap**, so vault P&L = **spread + carry, never directional FX**:
- Spread P&L: bid/ask captured around CIP per ticket.
- Carry: hedge inventory earns the rate differential (forward points = textbook FX swap-desk revenue).
- Margin fees on open positions.
Depositors get *"USD yield from FX flow"* — not emissions, not lending risk. **This is Tenor's vault, reused.**

**Risk machinery:** margined forwards (IM ~8% sized to the 99th-pct weekly EURUSD move ~1.5%; MM ~4%), continuous mark-to-market vs a **medianized dual-source oracle** (App Kit mid + ECB reference), per-block price-move circuit breaker, keeper liquidations, cash settlement in USDC at fixed weekly expiries.

### Only-possible-on-Arc thesis (state verbatim)
> *"A forward is a promise that survives until expiry — which is why TradFi wraps it in credit. On Arc, three properties replace the credit line: (1) **deterministic sub-second finality** → real-time variation margin + instant, non-reorg-able liquidation (you can run a CCP's risk engine per block); (2) **USDC-native gas** → margin top-ups/settlement cost a known fraction of a cent, collapsing the min ticket from $1M to $1; (3) **native USDC+EURC** → both legs settle atomically, 24/7, including Saturday when every TradFi desk is closed."*

**Capital-markets flourish:** the forward curve *is* the implied USD–EUR rate differential ⇒ **Contango bootstraps the first on-chain stablecoin FX yield curve**, a primitive other Arc protocols consume. *"The forward curve is what capital markets are built on. Arc doesn't have one. We built it."*

### Architecture & Circle-stack mapping
| Component | Role | Circle/Arc primitive |
|---|---|---|
| `ForwardEngine.sol` | Margined USDC/EURC forward book: open/margin/MTM/liquidate/cash-settle; fixed weekly expiries | Arc EVM; USDC-native gas; sub-second finality makes the margin loop safe |
| `CarryVault.sol` (ERC-4626) | Desk balance sheet; holds EURC hedge inventory, accrues spread+carry | Arc; USDC/EURC native (**from Tenor**) |
| `RateOracle.sol` + keeper | Medianized spot (App Kit mid + ECB ref) + SOFR/€STR fixings | App Kit Swap as one price source |
| Quant engine (Node/TS) | CIP fair value, inventory-skewed quoting, delta-hedger, liquidation keeper | **App Kit Swap** executes every hedge (first winner code to actually use it); custom spread fee = execution cost model (**from Catenaccio**) |
| Desk/keeper/agent wallets | Programmatic signing | **Circle Developer-Controlled Wallets SDK** |
| **Hedger Agent** (dual-track) | Autonomous agent, own wallet; watches a merchant wallet's EURC inflows, applies a hedge policy ("keep 90% of 30-day revenue USD-locked"), buys firm quotes, opens/rolls/settles forwards — unattended | Circle Wallets + **x402** (pays a nanofee per firm quote — clean, non-gimmick x402) |
| Cross-chain deposits | "Hedge from anywhere" | **Bridge Kit / CCTP / Gateway** (one thin integration) |
| Institutional path | `SpotVenue` interface: `AppKitSwapVenue` live; `StableFXVenue` stubbed | **StableFX** snap-in when Circle issues the key |
| Frontend (Next.js) | Live forward curve, trade ticket, vault APY, agent feed, liquidation console | — |

**Judging-language checklist hit verbatim:** conditional payments (margin locks); onchain automation (MTM + keeper liquidations + agent rolls); multi-step settlement (expiry = margin release + netted cash flow + hedge unwind, atomic); treasury/FX workflow via App Kits; legitimate dual-track (agent holds wallet, decides, pays & settles in USDC autonomously).

### Why it's unbeatable / fundable
- **Completes Circle's own roadmap** (spot → derivative). Reads like a company for the accelerator to fill its FX stack.
- **Wide-open lane** — differentiated on arrival vs. 18 payment-plumbing winners.
- **Real business:** SME/agent FX hedging, verifiably underserved (banks won't; Wise/Revolut don't hedge for you). Revenue = spread + margin fees. First customers who *literally cannot get an ISDA* = agents.
- **Quant credibility on the surface** (CIP, forward points, delta-neutral carry, inventory-skewed quoting) — signals "this founder is a quant," which no other team matches.
- **Builder fit:** remix of Tenor (vault/tokenization), Catenaccio (MM loop), PARIAH/PITBOSS (settlement engines), polished dashboards — not a cold start.

### 3-minute demo script
- **0:00–0:20 Hook:** *"It's Saturday. EURUSD gaps 80 pips. Every hedging desk on Earth is closed. Maria — a Lisbon merchant paid in EURC with USD costs — is fine: her agent already rolled her hedge on Arc."* → live forward curve.
- **0:20–1:00 Instrument:** open a 30-day EURUSD forward, **$50** notional; margin lock final in <1s on ArcScan; gas = fractions of a cent, in USDC.
- **1:00–1:40 Desk:** quote vs CIP fair value w/ live SOFR/€STR; engine delta-hedges instantly on App Kit Swap (show swap tx); vault APY ticking; inject a price jump → keeper liquidates in one block.
- **1:40–2:20 Agent:** merchant wallet receives EURC → Hedger Agent (own wallet) detects exposure, pays x402 nanofee for a firm quote, opens forward, logs policy decision (timestamps prove unattended); show an expiry = one atomic multi-step settlement tx.
- **2:20–3:00 Vision:** `SpotVenue` slide (App Kit today, StableFX tomorrow); Gateway deposits from any chain; *"Arc now has a forward curve."* Ask: 8 weeks to mainnet-ready with StableFX access.

---

## 3-week build plan (final due 9 Aug) + red-team mitigations
- **Week 1:** contracts (`ForwardEngine`, `CarryVault`, `RateOracle`) + **Foundry invariant tests** (vault solvency, margin conservation) → deployed to Arc testnet (`https://rpc.testnet.arc.network`) by **day 7**.
- **Week 2:** quant engine (CIP + inventory-skewed quoting), App Kit Swap hedger, oracle keeper, Hedger Agent.
- **Week 3:** Next.js dashboard, CCTP deposit beat, 3-min video, deck, README (architecture diagram + explorer links). Anything not demo-visible by **day 16** → roadmap slide.

**Red-team fixes:** static testnet FX → oracle posts real ECB/Frankfurter EURUSD; demo **replays a real volatile week through real contracts** (never fake txs). Non-quant judges → lead with Maria + "lock a future rate, no bank, 24/7," math after the $50 ticket. Margin bug → keep it linear: one pair, cash-settled, fixed expiries, single margin tier. "Where's the yield?" → honest slide (spread = live mechanics; carry marked to real SOFR/€STR). Oracle/gap risk → medianized dual-source + circuit breaker + IM sized to 99th-pct move (show the histogram). StableFX key → build on App Kit Swap behind `SpotVenue`, request key on Discord week 1.

**Advanced-tech edge (roadmap slide):** ZK proof of correct, in-limits strategy execution — prove the desk obeyed risk limits without revealing alpha.

---

## Alternates (ranked)
**1. Meridian — autonomous CFO / treasury OS.** Policy-driven treasury agent: sweeps idle USDC cross-chain (Gateway/CCTP) into unified balance, holds FX to policy via App Kit Swap, ladders yield, runs conditional vendor payments, auditable on-chain decision log. Broadest stack use + obviously fundable; ranked below Contango because it's closer to the agent-bank lane past winners occupied and its quant depth is thinner (policy rules, not a strategy). *Its carry vault already lives inside Contango.*

**2. Pips — on-chain FX RFQ market-making desk.** Avellaneda–Stoikov MM quoting USDC/EURC (+cirBTC/USDC); LP vault owns inventory P&L; firm quotes over an x402-paid API. Genuinely quant, reuses Catenaccio; ranked third because it *competes with* App Kit Swap/StableFX rather than completing them ("Circle already does this").

**De-prioritized:** pure MEV-protection (Arc's deterministic finality already blunts it; off-narrative).

---

## Immediate next steps
1. Lock **Contango**. Checkpoint 2 (26 Jul) = repo + progress; Final (9 Aug) = MVP + 3-min video + deck; Demo Day 20 Aug.
2. Scaffold: Foundry/Hardhat on Arc testnet + Next.js dashboard + Node/TS quant engine + Circle Wallets; port CarryVault from Tenor and the quoting loop from Catenaccio.
3. Faucet USDC/EURC/cirBTC; wire App Kit Swap behind `SpotVenue`; request StableFX key on Build-on-Circle Discord.
