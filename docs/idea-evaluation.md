# Idea Evaluation — DeFi-track slate + judge scorecard

Two independent passes (main analysis + a Fable-5 research agent) both converged on **Contango** (originally "Outright") as the highest-EV DeFi-track idea. Below is the Fable pass's DeFi-only slate and judge scorecard, kept as the record of *why this idea beat the alternatives* and what the fallback is.

## The core insight
Every one of the 18 past Arc/Circle winners built the **payment-execution layer** (agent wallets, x402, escrow). Their actual code uses only Developer-Controlled Wallets + x402 — **zero** real use of App Kit Swap, Bridge, CCTP, Gateway, StableFX, or Paymaster; the only Solidity shipped is escrow/streaming/insurance. **Nobody built a quant DeFi product.** That empty lane is exactly Circle's strategic priority (FX / treasury / capital markets).

## The slate (all DeFi-track, protocol-first; any agent is an optional module)
1. **Contango** — 24/7 margined FX forwards + delta-neutral carry vault (CIP pricing, inventory-skewed MM, spread+carry).
2. **Repo** — intraday collateralized repurchase-agreement market (EWMA/GARCH dynamic haircuts, repo-rate curve).
3. **Ledger** — multilateral netting/clearing ("CLS for stablecoins"; min-cost-flow netting + atomic net settlement).
4. **Basis Bridge** — cross-chain interest-rate arbitrage harvester (CCTP + Gateway at the center).
5. **Ladder** — treasury duration-matching / cash-flow immunization (duration/convexity matching).
6. **CreditLine** — trade-finance letters-of-credit with on-chain PD credit scoring.
7. **VolTarget** — volatility-targeting reserve manager (EWMA vol / risk-parity rebalancing).
8. **Triangle** — atomic triangular + cross-chain flash arbitrage vault.
9. **Theta** — automated options vault (covered call / cash-secured put) on cirBTC/USDC (Black-Scholes, Greeks).
10. **Strip** — fixed-rate lending / zero-coupon curve bootstrapper (overlaps her Tenor — risks reading as recycled).
11. **Tide** — dynamic-fee AMM / LP inventory-risk manager (Glosten-Milgrom) — competes with App Kit Swap.

## Judge scorecard (Circle-judge hat, /10 each, /70 total)
| # | Idea | Only-Arc | Adv. flows | Stack depth | Grant fit | Novelty | Quant | 3-wk feasibility | Total |
|---|------|:--:|:--:|:--:|:--:|:--:|:--:|:--:|:--:|
| 1 | **Contango** | 9 | 9 | 8 | 10 | 10 | 9 | 7 | **62** |
| 2 | Repo | 9 | 8 | 7 | 9 | 9 | 8 | 7 | 57 |
| 3 | Ledger | 8 | 8 | 6 | 8 | 9 | 7 | 8 | 54 |
| 4 | Basis Bridge | 8 | 7 | 9 | 8 | 7 | 7 | 6 | 52 |
| 5 | Ladder | 6 | 7 | 8 | 8 | 5 | 6 | 8 | 48 |
| 6 | CreditLine | 6 | 8 | 6 | 7 | 7 | 6 | 7 | 47 |
| 6 | VolTarget | 7 | 6 | 7 | 6 | 6 | 7 | 8 | 47 |
| 8 | Triangle | 7 | 6 | 7 | 5 | 6 | 6 | 9 | 46 |
| 8 | Theta | 6 | 7 | 7 | 6 | 6 | 9 | 5 | 46 |
| 10 | Strip | 6 | 6 | 6 | 6 | 6 | 8 | 6 | 44 |
| 11 | Tide | 5 | 5 | 5 | 4 | 5 | 7 | 7 | 38 |

## Verdict
**Ship Contango, DeFi-first, agent demoted to an optional closing beat.** It wins on the two dimensions the brief weights most — strategic/grant fit (it's the literal next layer on StableFX) and novelty vs. the field — while being genuinely feasible because it remixes already-built assets (Tenor = the vault, Catenaccio = the MM loop).

**Is it truly DeFi?** Yes, structurally. Strip out the Hedger Agent entirely and the protocol fully exists and demos (ForwardEngine, CarryVault, RateOracle). The fix for any "this feels agentic" worry is *presentational*: lead the README/deck/first 100s of video with the protocol; mention the agent only in the last 30s as "also runs unattended."

**Fallback:** **Repo** (57) — same skill set (collateral lock, oracle-driven risk model, keeper liquidation), one fewer moving part (no FX leg / forward curve). Swappable in week 2 without restarting the clock if the margin/liquidation engine proves too complex to make demo-bulletproof.
