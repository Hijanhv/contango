# Contango — Brand

## Logo concept
The mark **is** the product: a **forward curve in contango**. A spot origin node (lower-left) rises along a curve that steepens then flattens across two **maturity nodes** (term structure) to a **settlement ring** at the far tenor (upper-right). The muted horizontal line is **spot**; the shaded wedge between it and the curve is the **contango gap** (forward − spot). Minimal, geometric, symbolic — premium Web3/DeFi style.

## Assets (in this folder)
| File | Use |
|---|---|
| `logo-mark.svg` | Symbol, source vector (edit while building) |
| `logo-mark-dark.png` | 1120×1120 dark app icon — profile / project avatar upload |
| `logo-mark-transparent.png` | 1024×1024 transparent — overlay on any dark surface |
| `logo-full.svg` | Mark + `CONTANGO` wordmark, source vector |
| `logo-full-dark.png` | Horizontal lockup on dark — headers, deck title, README hero |
| `logo-full-transparent.png` | Lockup, transparent |

## Palette
| Token | Hex | Use |
|---|---|---|
| Teal (spot / near tenor) | `#14E0B4` | gradient start |
| Cyan (mid curve) | `#28C4F0` | gradient mid |
| Violet (far tenor / future) | `#7C5CFC` | gradient end |
| Ink | `#0A0E17` | background / node fill |
| Ink deep | `#060911` | background edge |
| Slate (spot baseline) | `#4A5570` | muted line |
| Paper | `#EDF1F8` | wordmark / light text |

Gradient direction: lower-left → upper-right (follows the curve). 

## Typography
Wordmark: geometric sans — **Futura** (fallbacks: Century Gothic, Avenir Next, Helvetica Neue), medium weight, wide letter-spacing. Swap to a licensed geometric (e.g., Neue Montreal / Söhne / Space Grotesk) for the product UI if desired.

## Notes
- Designed for dark surfaces (Web3 convention). Maturity-node dots use an ink fill (read as cut-outs on dark).
- To render PNGs from the SVGs: `node ~/playwright-automation/render_contango.js`.
