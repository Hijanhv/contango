# Session Log — how we got to Contango

A record of the research and decisions from the terminal session (20–21 Jul 2026).

## 1. Understood the hackathon
Programmable Money Hackathon (Arc × Circle / Encode Club). Two tracks: **DeFi** (lending, borrowing, swaps, liquidity, FX, yield, payments, treasury, fintech infra) and **Agentic Economy**. One project may enter both. Prize = top ~8 teams → 8-week accelerator. Key dates: CP2 (repo) 26 Jul, Final (MVP + 3-min video + deck) 9 Aug, Demo Day 20 Aug.

## 2. Researched what Circle/Arc want (Playwright + WebSearch + context7)
- Arc = Circle's stablecoin-native L1: USDC-native gas, sub-second deterministic finality (Malachite), built for **institutional FX / treasury / capital markets**. Flagship: **StableFX** (RFQ FX engine, multi-currency stablecoins).
- Testnet reality: RPC `https://rpc.testnet.arc.network`, explorer `testnet.arcscan.app`; assets USDC/EURC/cirBTC via Circle faucet. **App Kit Swap** (USDC↔EURC, configurable spread fee) is open now; **StableFX** needs a Circle-issued API key. Oracles + CCTP + Gateway available. On Arc, USDC is native gas (18 decimals, `msg.value`).
- Docs: `docs.arc.io` (llms.txt index), `developers.circle.com` (indexed in context7 as `/websites/developers_circle`).

## 3. Downloaded & analyzed 18 past-winner repos (Playwright + gh)
Cloned winners from 3 hackathons into `~/arc-hackathon-winners/repos/`:
- **Agentic Commerce on Arc** (Jan 2026, 222 teams): OmniAgentPay (1st), NewsFacts, Arc Merchant (2nd), Arcent, RSoft Agentic Bank, InsuranceAI, ArcPay SDK, AI Merchant Studio, JoyKeep, VibeCard, FEIN. *(AIsaEscrow, Arcana private; RouterAI no repo)*
- **AI Agents on Arc with USDC** (NYC): Arc Pay (Superface), SOLRARC, ArcAgent. *(Tiba private)*
- **Circle Developer Bounties** (2024): MorphPay, Gatee, PUBSTACK, Gasorin.
- Beat lablab's Cloudflare with a **fresh-browser-per-URL** Playwright pattern; got Circle-bounty repos from DoraHacks BUIDL pages.

**Key finding:** winners are all *payment plumbing*. Their code uses only Developer-Controlled Wallets + x402 — **zero** real use of App Kit Swap/Bridge/CCTP/Gateway/StableFX/Paymaster; only Solidity is escrow/streaming/insurance. → **No quant DeFi exists. That lane is open, and it's Circle's strategic priority.**

## 4. Idea generation + judging (main analysis + a Fable-5 research agent)
- Two independent passes converged on the same insight (the empty "alpha layer").
- Explored a full DeFi-only slate (forwards, repo, netting/clearing, cross-chain rate arb, options vault, fixed-rate, AMM, etc.), scored as a Circle judge. Winner: **Contango** (62/70). Fallback: **Repo** (57). See `docs/idea-evaluation.md`.
- Confirmed Contango is structurally DeFi (agent module is deletable).

## 5. Decisions locked
- **Idea:** Contango — 24/7 on-chain FX forwards + delta-neutral carry vault (CIP pricing, inventory-skewed MM, spread+carry). DeFi-first; optional Hedger Agent for dual-track.
- **Name:** Contango (see `docs/naming.md`).
- **Logo:** forward-curve mark + wordmark (see `brand/`).
- **Build reuse:** Tenor (ERC-4626 vault) + Catenaccio (market-making loop) → dramatically de-risks the 3-week build.

## Tools / scripts used
- Playwright scrapers in `~/playwright-automation/`: `arc_scrape.js`, `find_repos.js`, `scrape_fresh.js`, `scrape_aiagents.js`, `scrape_dorahacks.js`, `render_contango.js`.
- `gh` (repo search + private-owner lookups), WebSearch, context7 (Circle docs), Fable-5 subagent (idea generation + judge scorecard).
- Raw scrape outputs: `~/arc-hackathon-winners/raw/`.
