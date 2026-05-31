# Secondary-text `sub` token AA contrast — Paper / Sepia (#1292 · Bug #285)

> Source of truth (design): `VReader Secondary Text Canvas.html` → `secondary-text-canvas-artboards.jsx`.
> Chat transcript: `chats/chat13.md`.
> Resolves the `needs-design` issue [#1292](https://github.com/lllyys/vreader/issues/1292) — the secondary-text facet of Bug #285 ([#1265](https://github.com/lllyys/vreader/issues/1265)). Sibling of the slider-track facet [#1273](https://github.com/lllyys/vreader/issues/1273) (`slider-track-rail.md`).
> Status: **design landed — implementation deferred** (recorded, not built; held for a separate go-ahead per the handoff convention).

## The gap

After #1277 routed the native SwiftUI `List` chrome (section headers, section
footers, value captions) to the design-system **`sub`** token, that secondary
text reads over the fixed cream panel sheet `#fcf8f0` at:

| theme | committed `sub` | ratio | bar |
|---|---|---|---|
| Paper | `rgba(29,26,20,0.55)` (ink @ 55%) | ~3.82:1 | clears the project's internal 3.0 secondary bar, **fails WCAG AA 4.5:1** |
| Sepia | `rgba(58,41,19,0.55)` (ink @ 55%) | ~3.36:1 | clears 3.0, **fails AA 4.5:1** |

Section headers, footers, and value captions are **real text** — they must
clear AA. Per Rule 51 the fixer can't pick a darker alpha by hand (how dark
secondary text reads is a visual-weight decision); it needs a design token.
Bug #285 itself was closed having resolved every element to the project's 3.0
self-bar; this AA bump was deliberately carved out as enhancement #1292.

## Decision (binding)

Darken the **light-family `ReaderThemeV2.sub` token from each theme's ink @ 55%
to ink @ 68%.**

| theme | `sub` (proposed) | derivation | ratio over `#fcf8f0` |
|---|---|---|---|
| Paper | `rgba(29,26,20,0.68)` | ink @ 68% | **5.81:1** ✓ AA |
| Sepia | `rgba(58,41,19,0.68)` | ink @ 68% | **4.88:1** ✓ AA |
| Dark  | `rgba(216,210,197,0.5)` | unchanged | out of scope (see below) |
| OLED  | `rgba(185,182,176,0.5)` | unchanged | out of scope |

- **Light family = each theme's own `ink` at 68%** — one rule, not two hand-picked
  greys, so the token keeps each theme's warmth (Paper near-black, Sepia brown).
  Exactly mirrors #1273's `ink @ 22%` rail derivation.
- **No call sites change** — the List chrome already reads `t.sub` after #1277.
  This is a single token-value change.
- **Dark / OLED unchanged** — Bug #285 is light-family only.

## Why 68% (not 62%, not 78%)

The token is **shared across Paper + Sepia**, so the floor is set by the harder
case — **Sepia**. 68% is the *smallest* unified alpha that clears AA in both:

| candidate | Paper | Sepia | verdict |
|---|---|---|---|
| ink @ 55% (current) | 3.82:1 | 3.36:1 | reject — the bug |
| ink @ 62% | passes | **~4.3:1, still fails** | reject — a unified token can't stop where Sepia fails |
| **ink @ 68%** | **5.81:1** | **4.88:1** | **pick — smallest unified alpha clearing both** |
| ink @ 78% | lots of margin | lots of margin | alt — crowds primary ink, flattens the secondary hierarchy |

Primary ink stays ~13:1 on cream, so secondary at 5.81:1 is comfortably lighter
— headers/footers/captions still read as secondary. **A legibility lift, not a
promotion to primary.**

## Rejected alternative

A dedicated **`subAA`** token (lift only the List chrome, keep `sub` light) was
rejected: two near-identical greys invite mis-application, and **all** `sub`
text is real text that deserves AA. One token, darkened.

## Out of scope — recommended follow-up

Dark / OLED secondary text also sits at **~3.7:1** over their `#222020` sheet
(also under AA). The canvas measures this honestly (§5) rather than silently
claiming it's fine — but it's a **separate visual-weight call** (a lighter ink
on a darker sheet), not this light-family token change. Recommended as a matched
follow-up; **not filed unilaterally** — surface to the user.

## Implementation pointer (deferred — do NOT build without go-ahead)

- In `vreader/Models/ReaderThemeV2.swift`, change the Paper and Sepia `sub`
  token from ink @ 0.55 → ink @ 0.68 (Paper `rgba(29,26,20,0.68)`, Sepia
  `rgba(58,41,19,0.68)`). Leave Dark/OLED untouched.
- A RED contrast test belongs in `ReaderSettingsPanelContrastTests` /
  `WCAGContrastTests`: assert Paper/Sepia `sub` over the cream surface now clears
  **4.5:1** (it currently asserts only the 3.0 self-bar).
- This closes the **secondary-text facet** of Bug #285. The slider-track facet
  shipped via #1273 (`ReaderThemeV2.sliderTrack`, v3.41.6).
