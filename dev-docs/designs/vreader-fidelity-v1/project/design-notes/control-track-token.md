# Control-track token — Paper / Sepia (#1329 · Bug #298)

> Source of truth (design): `VReader Control Track Canvas.html` → `control-track-canvas-artboards.jsx`.
> Chat transcript: `chats/chat14.md`.
> Resolves the `needs-design` issue [#1329](https://github.com/lllyys/vreader/issues/1329) — the **control-track facet** of Bug #298. Third sibling of #1273 (slider rail, shipped, `sliderTrack`) and #1292 (secondary text, `sub`).
> Status: **design landed — implementation deferred** (recorded, not built; held for a separate go-ahead per the handoff convention).

## The gap

On the Reader Display panel (`ReaderSettingsPanel.swift`), `.tint(accentColor)`
(line 170) colors only the **ON** toggle track and the **selected** segment fill.
It never touches:

- the **"Custom Background"** `Toggle` in its **OFF** state — the track is iOS
  `.systemFill`, a cold pale gray that computes to **~1.19:1** over the cream
  sheet `#fcf8f0` (near-invisible);
- the **"Scroll / Paged"** segmented control trough (unselected surface) — same
  `.systemFill`, same ~1.19:1; the pale selected pill also washes into it.

Per Rule 51 the fixer can't hand-pick a track alpha (visual-weight decision); it
needs a token. This is the third contrast facet of the panel (rail #1273 + sub
text #1292 are the first two).

## Decision (binding)

Add a per-theme **`ReaderThemeV2.controlTrack`** token. Light family = each
theme's **ink @ 30%**.

| theme | `controlTrack` | derivation | track vs sheet |
|---|---|---|---|
| Paper | `rgba(29,26,20,0.30)` | ink @ 30% | ~1.9:1 |
| Sepia | `rgba(58,41,19,0.30)` | ink @ 30% | ~1.9:1 |
| Dark  | `rgba(255,255,255,0.16)` | unchanged | already reads on `#222020` |
| OLED  | `rgba(255,255,255,0.16)` | unchanged | already reads |

- **Light family = each theme's `ink` at 30%** — same ink-derived family as
  #1273's rail (22%) and #1292's sub text (68%), so the track inherits the
  theme's warmth (Paper near-black, Sepia brown) instead of cold system gray.
  One rule, not four magic numbers.
- Drives the **OFF toggle track** and the **segmented trough / unselected
  segment**. `.tint(accent)` stays for ON / selected.
- **Dark / OLED unchanged** — the low-contrast bug is light-family only; white
  tracks on the dark sheet already read.

## Why 30% (not the rail's 22%)

The slider rail (22%) leans on a high-contrast fill + thumb **on the same
element**. A control track stands alone as the OFF / inactive surface, so it
carries its own weight:

| candidate | track vs sheet | verdict |
|---|---|---|
| `.systemFill` (current) | ~1.19:1 | reject — invisible, the bug |
| ink @ 22% (reuse rail) | ~1.6:1 | alt — warm + in-family but reads as a faint hairline on a bare control |
| **ink @ 30%** | **~1.9:1** | **pick — reads unmistakably as an inactive control, gives the selected pill a darker trough, stays quiet** |
| ink @ 40% | heavier | alt — starts rivalling the accent ON-track; "off" stops reading as off |

A pure 3:1 boundary would need ≈ ink @ 48%+ — a heavy mid-gray slab that reads
like a *disabled* control and crowds the accent. So 30% is the smallest weight
that reliably reads as an inactive control without competing with "on".

## Selected pill — unchanged (token-wise)

The selected segment stays the **elevated light pill** (`#fffdf7` light /
`#3a3530` dark) with its shadow + 0.5px hairline + 600-weight label. It now reads
simply because it floats on the darker `controlTrack` trough, not because the
trough was made invisible. **Open question surfaced by the designer**: if the team
later wants a dedicated `controlSelected` token for the pill too, that can be
split out — default is to keep the elevated light pill, no new token.

## WCAG 1.4.11

State identification is met without the track clearing 3:1: the toggle's white
knob position (~17:1) + the accent ON-track distinguish on/off; the segmented
selection is the pill's elevation + bold label. The track is a visible-extent
surface, deliberately tuned below 3:1 for visual weight — an explicit design
call (Rule 51), mirroring the shipped rail precedent.

## Implementation pointer (deferred — do NOT build without go-ahead)

- Add `controlTrack` to `ReaderThemeV2` (per theme, values above).
- Wire the **segmented control** trough / unselected segment to `t.controlTrack`.
- Wire the **OFF toggle track** to `t.controlTrack` — **note the complexity**:
  SwiftUI/UIKit has **no public API** for a `UISwitch` off-track color, so this
  needs a **custom toggle style** (or a background capsule behind the switch),
  not a one-line modifier. This WI is larger than the token add alone.
- Tests in `ReaderSettingsPanelContrastTests`: OFF track vs sheet **≥ 1.8:1**
  (light family), and OFF-track ≠ accent ON-track (**Δ ≥ 2.5:1**) so on/off stay
  distinguishable.
- This closes the **control-track facet** of Bug #298. Siblings: #1273
  (`sliderTrack`, shipped v3.41.6) and #1292 (`sub`, designed).
