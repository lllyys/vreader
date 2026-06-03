# Feature #74 — Locate "bloom" on highlight/note landing (TXT/MD)

Committed design: `dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-highlight-landing.md`
(Rule 51 satisfied — building from the design, not inventing UI).

## Problem

Tapping a row in the Notes/Highlights list jumps to the saved range, but there is
NO transient cue. Worse, `handleNavigateToLocator` sets a temporary highlight
equal to the persisted range, and `HighlightableTextView.setHighlightRanges`
**dedups it away** (`active == persisted` → dropped, line 156-161), so the
emphasis is a literal no-op. The design commits a single **"locate bloom"** (wash
value-lift 0.42→0.86 + a same-hue focus ring + soft glow, ~1.5s, once).

## Work-item sequencing

- **WI-1 (this PR, FOUNDATIONAL — no user-visible delta)**: the landing RENDER
  LAYER. A separate `landingHighlight` in `HighlightingLayoutManager` painted
  apart from persisted/search (so it renders even when its range == a persisted
  range — defeats the dedup no-op), parameterized by an `intensity` (0…1). A pure
  `LandingBloomPaint` helper maps `(intensity, themeFamily)` → the wash alpha,
  ring width, glow radius, and glow alpha per the design's §3/§6 knobs. **No
  user-visible delta because nothing in WI-1 ever SETS `landingHighlight` (no
  trigger ships until WI-2) — the layer is dormant.** (Independently, the
  replace-don't-stack render rule in the surface section makes even a
  hypothetically-set resting layer byte-identical to the persisted highlight, so
  WI-2 inherits no latent darkening.) → foundational tier, unit-tested, no device
  verification.
- **WI-2 (behavioral, FINAL — device-verified)**: the bloom ANIMATION driver
  (`CADisplayLink` motion curve rise/hold/decay per §3; Reduce-Motion static-hold
  per §5; interruptible per §3), **scroll-to-prominent** (§4, ~38% band), and the
  **navigate-from-list trigger** (fire the bloom when the nav target range equals
  a persisted highlight, instead of the dropped search highlight). Device-verified
  across themes.

## Surface area (WI-1)

- `vreader/Views/Reader/LandingBloomPaint.swift` (new) — pure, UIKit-light value
  helper:
  - `enum LandingBloomThemeFamily { case light, dark }`
  - `struct LandingBloomPaint` with `washAlpha`, `ringWidth`, `glowRadius`,
    `glowAlpha` computed from `intensity` (clamped 0…1) and family.
    **washAlpha = lerp(HighlightPaintColor.fillAlpha, 0.86, i)** — Gate-2 round-1
    Medium: the baseline is the CURRENT persisted fill (`fillAlpha = 0.4`), NOT
    the design's nominal 0.42, so that at `intensity 0` the landing wash is
    byte-identical to the persisted wash → "resting == persisted" and zero
    visible delta actually hold (the design's 0.42 ≈ the code's 0.4; we align to
    code so WI-1 is provably dormant). The peak 0.86 is the design value.
    ringWidth = 1.6 * i; glowRadius = 16 * i;
    glowAlpha = (family == .light ? 0.55 : 0.85) * i. Pure → unit-tested.
- `vreader/Views/Reader/HighlightableTextView.swift`
  - `HighlightingLayoutManager`: add
    `var landingHighlight: (range: NSRange, colorName: String, intensity: CGFloat, family: LandingBloomThemeFamily)?`
    and, in `drawBackground` AFTER persisted + search, paint it: the wash fill
    (swatch @ `washAlpha`), a solid-swatch ring (stroke the enclosing rects at
    `ringWidth`), and a glow (`ctx` shadow, hue @ `glowAlpha`, blur `glowRadius`)
    — using `box-decoration-break: clone` semantics (per line-fragment rects, via
    the same `enumerateEnclosingRects`).
    **Render rule — the landing wash REPLACES (does not stack on) the persisted
    fill for its range (Gate-2 round-2 Medium):** the design's wash "value-lifts"
    — it is the SAME wash brightening (0.4→0.86), NOT a second translucent fill
    overlaid. Two stacked 0.4-alpha fills composite DARKER, so a separate layer at
    `intensity 0` would visibly darken a persisted highlight. Therefore
    `drawBackground` SKIPS painting any persisted highlight whose
    `range == landingHighlight.range` (the feature's case — a Notes/Highlights tap
    lands exactly on a saved range) and paints the landing wash for that range
    instead. At `intensity 0` the landing wash is the same 0.4 alpha the suppressed
    persisted fill would have drawn → byte-identical render (no darkening); at
    `intensity 1` it is the single brightened 0.86 wash. This both defeats the
    dedup no-op (the landing layer renders for an equal range) AND keeps the wash a
    single lifting layer, never a stack.
    **Two implementation requirements (Gate-2 round-1 notes):** (a) the early
    `drawBackground` guard `!persistedHighlights.isEmpty || searchHighlightRange != nil`
    must ALSO admit `landingHighlight != nil`, else a landing-only frame never
    paints; (b) wrap the ring + glow painting in `ctx.saveGState()` /
    `ctx.restoreGState()` so the shadow/stroke state never leaks into the
    persisted/search fills within the same draw pass.
  - `HighlightableTextView.setLandingHighlight(range:colorName:intensity:family:)`
    + `clearLandingHighlight()` — set the layer + invalidate display. (No
    animation here — that's WI-2's driver calling `setLandingHighlight` per frame.)
  - `HighlightPaintColor`: add `solidSwatch(for:)` (opaque design swatch for the
    ring/glow hue) + `fill(for:alpha:)` (variable-alpha wash) — small additive
    helpers; the existing `fill(for:)`/`searchHighlight` are unchanged.

### Files OUT of scope

- The bloom animation driver, scroll-to-prominent, Reduce-Motion, and the
  navigate-from-list trigger — WI-2.
- EPUB/Foliate + PDF landing (design §7 — TXT/MD first).
- The Notes/Highlights list UI (`vreader-annotations.jsx`) — unchanged.

## Prior art / precedent

`HighlightingLayoutManager.drawBackground` already paints persisted + search
highlights without mutating text storage (Bug #47 v12 — the safe path). WI-1 adds
one more painted layer in the same `enumerateEnclosingRects` idiom. The
`NamedHighlightColor.hex` swatch + `HighlightPaintColor.fill` resolution are
reused for the wash/ring/glow hue.

## Test catalogue (WI-1)

`vreaderTests/Views/Reader/LandingBloomPaintTests.swift`:

- `paint_atRestIntensity_matchesPersistedSourceAlpha` — `intensity 0` → washAlpha
  == `HighlightPaintColor.fillAlpha` (0.4), ring/glow widths 0. This proves the
  resting wash's SOURCE alpha equals the persisted fill's; combined with the
  replace-don't-stack render rule (the landing wash is painted INSTEAD of the
  suppressed persisted fill, not over it), the resting render is identical — no
  darkening. (The render-rule decision is a separate pure test below; the
  composited render itself is device-confirmed in WI-2.)
- `suppressesPersisted_whenLandingRangeEqualsPersisted` — the pure decision
  `LandingBloomPaint.suppressesPersisted(persistedRange:landingRange:)` returns
  true iff the ranges are equal (so `drawBackground` skips the persisted fill and
  the landing wash replaces it — no stacked-alpha darkening).
- `paint_atPeakIntensity_liftsWashAndRingAndGlow` — `intensity 1` → washAlpha 0.86,
  ringWidth 1.6, glowRadius 16.
- `paint_midIntensity_lerpsLinearly` — `intensity 0.5` → washAlpha ==
  (fillAlpha + 0.86)/2 (0.63).
- `paint_glowAlpha_lightVsDarkFamily` — light = 0.55·i, dark = 0.85·i (design §6).
- `paint_intensity_clampedToUnitRange` — `< 0` / `> 1` clamp.

(The `drawBackground` painting + the dedup-defeat are exercised by WI-2's device
verification; the pure paint-param math is the WI-1 unit seam.)

## Risks + mitigations

- **Glow performance** — a CGContext shadow per line-fragment each frame could be
  costly. WI-1 only paints a single static frame on demand. **Gate-2 round-1
  Medium correction:** the current invalidation seam is whole-glyph
  (`invalidateDisplay(forGlyphRange: 0..<glyphCount)`, line 162-164) — `drawBackground`
  only DRAWS visible glyphs, but the invalidation scope is the whole text. So WI-2
  must either (a) tighten the animation's invalidation to the landing range /
  current viewport, or (b) accept profiling + graceful glow degradation (ring +
  wash only, still legible per §6) as an explicit Gate-5 acceptance item. WI-1
  inherits the existing whole-glyph invalidation (a single on-demand frame, not a
  per-frame loop), so this is a WI-2 concern.
- **Theme family resolution** — WI-1 takes `family` as a parameter; WI-2 resolves
  it from the active `ReaderThemeV2` (light: paper/sepia; dark: dark/oled/photo).
- **No regression to persisted/search painting** — the landing layer is additive;
  `persistedHighlights` / `searchHighlightRange` paint paths are untouched.

## Backward compat

WI-1 adds an optional layer that is nil until set; no caller sets it yet, so there
is zero behavioral change. The only edit to the existing paint paths is the
equal-range persisted-wash suppression, which is a no-op while `landingHighlight`
is nil (every persisted highlight still paints). No schema/persistence/
notification changes.

## Revision history

- **v1** (2026-06-03) — initial plan.
- **v2** (2026-06-03) — Gate-2 Codex audit round 1 (`/tmp/feat74-planaudit.txt`):
  confirmed the WI split, the separate-layer dedup-defeat, and the code
  assumptions (`drawBackground`, `enumerateEnclosingRects`, swatch resolution).
  Found 2 Medium + 2 implementation notes — all fixed in v2:
  - **Medium (wash baseline)** → washAlpha lerps from `HighlightPaintColor.fillAlpha`
    (0.4, the actual persisted fill), NOT the design's nominal 0.42, so
    `intensity 0` is byte-identical to persisted and "no visible delta" provably
    holds.
  - **Medium (perf-mitigation overstated)** → risk section corrected: the seam
    invalidates whole-glyph today; WI-2 tightens invalidation or accepts
    profiling + glow degradation.
  - **Notes** → drawBackground guard must admit `landingHighlight`;
    `saveGState`/`restoreGState` around ring+glow.
- **v3** (2026-06-03) — Gate-2 round 2 (`/tmp/feat74-planaudit-r2.txt`): 1 Medium
  — matching the source alpha doesn't make the RENDER equal, because a separate
  landing layer at `intensity 0` still composites a second 0.4 fill OVER the
  persisted one and darkens it. Fixed: added the **replace-don't-stack render
  rule** (the landing wash REPLACES the persisted fill for an equal range — the
  design's "wash value-lifts" is a single wash, not a stack), restated WI-1's
  "no visible delta" as resting on the layer being DORMANT in WI-1, and added a
  pure `suppressesPersisted(persistedRange:landingRange:)` decision + its test.
