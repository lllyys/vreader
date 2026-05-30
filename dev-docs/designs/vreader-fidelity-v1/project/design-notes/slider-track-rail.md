# Slider-track rail contrast — Paper / Sepia (#1273 · Bug #285)

> Source of truth (design): `VReader Slider Track Canvas.html` → `slider-track-canvas-artboards.jsx`.
> Chat transcript: `chats/chat11.md`.
> Resolves the `needs-design` carve-out [#1273](https://github.com/lllyys/vreader/issues/1273) of Bug #285 ([#1265](https://github.com/lllyys/vreader/issues/1265)).
> Status: **design landed — ready to implement (implementation deferred; not built in the handoff session).**

## The gap

The Reader **Display** panel's `SettingsSliderRow` (Font Size, Line Spacing) draws its unfilled
track with the committed inline value `t.isDark ? rgba(255,255,255,0.1) : rgba(0,0,0,0.1)`
(`vreader-panels.jsx` · `SliderRow`). Over the panel's fixed cream sheet `#fcf8f0` the light-family
value computes to ~1.25:1 — a cold pure-black smudge that "reads as no rail". That is the slider
sub-symptom of Bug #285. Per Rule 51 the fixer could not pick a darker opacity by hand (choosing
how dark the rail looks is a visual-weight decision); it needed a design token.

## Decision (binding)

Introduce a per-theme **`ReaderThemeV2.sliderTrack`** token and replace the inline
`t.isDark ? rgba(255,255,255,0.1) : rgba(0,0,0,0.1)` in the slider row with `t.sliderTrack`.

| theme | `sliderTrack` | derivation |
|---|---|---|
| Paper | `rgba(29,26,20,0.22)` | ink @ 22% |
| Sepia | `rgba(58,41,19,0.22)` | ink @ 22% |
| Dark  | `rgba(216,210,197,0.12)` | unchanged weight |
| OLED  | `rgba(185,182,176,0.12)` | unchanged weight |

- **Light family = each theme's own `ink` at 22%** — one rule, not four magic numbers, so the rail
  inherits the theme's warmth (Paper near-black, Sepia brown) instead of a cold pure-black. Lifts the
  rail from ~1.25:1 to ~1.6:1.
- **Dark / OLED keep their current weight** — the low-contrast bug is light-family only; the
  white-on-dark rail already reads.
- **Unchanged**: accent fill (theme accent, ~7:1), the 22pt white thumb, and its `rgba(0,0,0,0.04)`
  shadow ring.
- **State-independent**: the token is the same in default, dragging, min (rail fully exposed — the
  stress case), and max (rail fully covered). Verified in the canvas's §4.

## Why ~1.6:1 and not a 3:1 slab

WCAG 1.4.11 (graphical-object contrast) is satisfied by the **fill + thumb** (both ≫ 3:1), which are
what convey the slider's value/state. The rail is decorative extent. Clearing 3:1 would need ≈ ink @
60%+ — a heavy slab the design explicitly rejects as out-of-character. `ink @ 22%` is the smallest
lift that reliably reads as a rail. This is a deliberate design call, not an oversight.

## Candidates considered (measured in-canvas)

| candidate | verdict | why |
|---|---|---|
| `black @ 10%` (current) | reject | cold pure-black at low alpha dissolves into warm cream — the bug |
| `rule` token | reject | warmer, but it's the divider weight — barely above current |
| **`ink @ 22%`** | **pick** | tracks each theme's warmth; reads clearly; stays light |
| `ink @ 32%` | alt | heavier opt-in if the panel later wants more weight (nears 2:1) |

## Implementation pointer (deferred — do NOT build without go-ahead)

- Add `sliderTrack` to `ReaderThemeV2` (per theme, values above).
- In the slider row, replace the inline rail expression with `t.sliderTrack`.
- This closes only the **rail** sub-symptom of Bug #285. The text-legibility half (native List chrome
  → theme tokens; `sub`-token AA) ships separately under #285 itself.
