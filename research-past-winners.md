# Arc × Circle Hackathon — Past Winners Codebase Archive

Research archive for the **Programmable Money Hackathon (Arc × Circle / Encode Club)**.
Collected via Playwright browser automation (lablab.ai project pages + DoraHacks BUIDL pages) and the GitHub API.

- **18 winner repositories cloned** (shallow, `--depth 1`) across **3 Arc/Circle hackathons**
- **4 unavailable** (repo set private after judging, or no public repo linked)
- Local root: `~/arc-hackathon-winners/repos/`
- Raw scrape data + full project write-ups: `~/arc-hackathon-winners/raw/` (see `raw/projects/*.txt`)

`circle/arc-hits` = count of files referencing x402 / CCTP / @circle / StableFX / Paymaster / Gateway / USDC / developer-controlled wallets — a rough proxy for how deeply each project wired the Circle/Arc stack.

---

## 1. Agentic Commerce on Arc  (Jan 9–24, 2026 · 222 teams · 1,200+ builders · Circle + Arc + NativelyAI + Google)

`repos/agentic-commerce-on-arc/`

| Project | Placement | Stack | Repo | Local dir | circle/arc-hits |
|---|---|---|---|---|---|
| **OmniAgentPay** | 🥇 1st overall ($20k) | Python SDK | `omniagentpay/omniagentpay` | `omniagentpay_1st-place` | 56 |
| **NewsFacts** | 🥇 1st on-site | Node | `kirilligum/newsfacts-arc-hackathon-260123` | `newsfacts_1st-onsite` | 20 |
| **Arc Merchant** | 🥈 2nd ($10k) | Node/Next | `ortegarod/arc-merchant` | `arc-merchant_2nd-place` | 25 |
| **AIsaEscrow** | 🥈 2nd | — | `AIsa-team/AIsaPay-Arc-hackathon` | ❌ **PRIVATE** | — |
| **Arcent** | Gemini Honorable | Node | `cutepawss/arcent` | `arcent_gemini-honorable` | 17 |
| **RSoft Agentic Bank** | Featured | Node | `rsoft-latam/rsoft-agentic-bank-band` | `rsoft-agentic-bank` | 4 |
| **InsuranceAI** | Featured | Hardhat/Solidity/Python | `subal235/InsuranceAi-Lablabai` | `insuranceai` | 20 |
| **Arcana** | Featured | — | `Aypp23/Arcana` | ❌ **PRIVATE** | — |
| **ArcPay SDK** | Featured | Node/Hardhat/Solidity/Next | `Himess/arcpay` | `arcpay-sdk` | **206** |
| **AI Merchant Studio** | Featured | Next.js | `yashwanth-3000/arc` | `ai-merchant-studio` | 36 |
| **JoyKeep** | Featured | Solidity | `bear3012/joykeep_lablab` | `joykeep` | 116 |
| **VibeCard** | Featured | Node | `pbudlong/vibecardnet` | `vibecard` | 30 |
| **FEIN of the Gemini** | Featured | Node | `ahmadrmq/FEIN` | `fein-of-the-gemini` | 16 |
| **RouterAI** | Featured | — | no public repo linked | ❌ **N/A** | — |

**Theme:** overwhelmingly *agentic* — autonomous agents paying via **x402 nanopayments**, agent "banks," escrow, and merchant/storefront infra. OmniAgentPay (winner) = a safety-kernel SDK wrapping Circle Developer-Controlled Wallets with atomic spending guards (budget caps, rate limits, whitelists). ArcPay SDK is the most stack-dense codebase (206 hits) — a full payment SDK with Solidity contracts.

---

## 2. AI Agents on Arc with USDC  (NYC · 95 submissions · "first ever to build on Arc")

`repos/ai-agents-on-arc-usdc/`

| Project | Placement | Stack | Repo | Local dir | circle/arc-hits |
|---|---|---|---|---|---|
| **Tiba** (AI medical billing) | 🥇 1st | — | `richiejeremiah/doclittle-platform` | ❌ **PRIVATE** | — |
| **Arc Pay** (Superface team) | 🥈 2nd | Node (360 files) | `superfaceai/arcpay` | `arcpay_2nd-place` | 63 |
| **SOLRARC** (USDC-settled RWA) | 🥉 3rd | — | `MRsteeds14/SOLRARC` | `solrarc_3rd-place` | 9 |
| **ArcAgent** (WhatsApp USDC) | Eleven Labs Award | Python/Next | `andyanalog/arc-agent` | `arcagent_elevenlabs-award` | 8 |

**Theme:** AI-driven *intent* → deterministic on-chain USDC execution. RWA settlement (SOLRARC) is the closest to the DeFi/quant direction. `superfaceai/arcpay` is a production-grade codebase (real company) — best reference for engineering quality.

---

## 3. Circle Developer Bounties — Group 1  (2024 · not Arc-specific, but core Circle stack)

`repos/circle-developer-bounties/`

| Project | Focus | Stack | Repo | Local dir | circle/arc-hits |
|---|---|---|---|---|---|
| **MorphPay** | Multichain USDC gateway, **CCTP v2**, cross-chain treasury | Node/Next | `jintukumardas/morph-pay` | `morphpay` | 17 |
| **Gatee** | Ticketing, CCTP cross-chain pay, ERC-1155 | Node/Solidity/Next | `ridhoizzulhaq/Gatee-Github` | `gatee` | 5 |
| **PUBSTACK** | Creator payments, **Circle Wallets + Gas Station** (gasless) | Node/Next | `AdedamolaXL/pubstack` | `pubstack` | 10 |
| **Gasorin** | Pay gas in USDC via **Circle Paymaster** + WalletConnect | Node/Next | `chiranjeev13/gasorin` | `gasorin` | 16 |

**Theme:** canonical Circle-stack integrations — CCTP, Wallets, Gas Station, Paymaster. Best reference for *how the Circle SDKs are actually called* in real code.

---

## Unavailable (4)
- **AIsaEscrow** — `AIsa-team/AIsaPay-Arc-hackathon` (private)
- **Arcana** — `Aypp23/Arcana` (private/removed after judging)
- **Tiba** — `richiejeremiah/doclittle-platform` (private)
- **RouterAI** — no public repo linked on project page

## How this was collected
- `playwright-automation/find_repos.js` — seed discovery
- `playwright-automation/scrape_fresh.js` / `scrape_aiagents.js` — **fresh-browser-per-URL** pattern to beat lablab's Cloudflare (only the first hit per fresh browser passes)
- `playwright-automation/scrape_dorahacks.js` — DoraHacks BUIDL pages
- `gh api` / `gh search` — repo resolution + private-repo owner lookups
