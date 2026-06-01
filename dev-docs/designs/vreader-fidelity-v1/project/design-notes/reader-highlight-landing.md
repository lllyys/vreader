# Highlight-landing locate indicator — the "locate bloom"

> Resolves [#1343](https://github.com/lllyys/vreader/issues/1343). Parent feature [#74](https://github.com/lllyys/vreader/issues/74) (`docs/features.md`).
> Source of truth: `VReader Highlight Landing Canvas.html` (every state across themes).
> Filed under `dev-docs/designs/vreader-fidelity-v1/` alongside `reader-navigation.md` and `needs-design-issues.md`.

When the reader taps a row in the Notes/Highlights list, `handleNavigateToLocator` jumps to the
saved range. The persisted highlight already paints at the spot — but there is **no transient cue**
that says *"here it is."* Worse, the current code path sets a temporary highlight equal to the
persisted one, and `HighlightableTextView.setHighlightRanges(persisted:active:)` dedups it away
(temp == persisted), so the emphasis is a literal no-op. This note commits the cue.

---

## 1. Decision at a glance

| | Decision |
|---|---|
| **Treatment** | **Locate bloom** — a single confident value-lift of the existing highlight wash + a same-hue focus ring with a soft outer glow that blooms once and settles. **Not** a repeated pulse/strobe. |
| **Colour interaction** | **Brighten + outline in the highlight's own hue.** The wash lifts from its resting ~0.42 alpha to ~0.86, gains a 1.6px solid-swatch outline and a soft glow, then decays back. The highlight is **never** recoloured to the theme accent — its colour is its identity. |
| **Motion curve + duration** | Fast rise (~140ms, ease-out), brief hold, slow decay back to resting over the remainder. **Total ≈ 1.5s, fires once** per navigation. |
| **Off-screen at landing** | **Scroll-to-prominent, then bloom.** Reposition so the highlight sits in the reading band (~38% from top of the content area), settle, *then* fire the bloom. Never bloom on a highlight that is clipped or jammed against the chrome. |
| **Reduce-Motion** | No bloom, no scale, no glow spread. The wash jumps to peak with a static solid outline, **holds ~1.2s, then a single opacity cross-fade** back to resting. One opacity transition, zero movement. |
| **De-dup fix** | The transient emphasis is a **separate render layer** keyed by `landingHighlightID + nonce`, not a second entry in the persisted/active range set — so it can equal the persisted range and still render. Closes the dedup no-op the issue calls out. |

---

## 2. Why a bloom, and why only once

The issue offers a menu: *pulse / flash / glow / scroll-to-prominent*. We reject the ones that read as
**alerts**:

- **Repeated pulse / strobe** — a blinking highlight reads as an error or a notification badge, not
  "found it." It also fights the only other reader motion cues we've designed (the tap-zone hint
  flash and the skeleton-pulse, `reader-navigation.md`), both of which are deliberately *quiet* and
  one-shot. A nervous strobe would be the loudest thing in a reading app.
- **Hard flash to white / accent** — momentarily destroys the highlight's colour, which is exactly
  the thing the user was navigating *to*. They made a *green* note; a white flash erases that for a
  beat.

A **single bloom** — the wash briefly brightens and a halo blooms out and fades — is the gentlest
treatment that still unambiguously draws the eye. It says "here," once, and then the page is just a
page again. It reuses the highlight's existing wash (continuity) rather than overlaying a foreign
shape.

### The wash is the hero, the ring is the locator

Two layers move together:

1. **Wash value-lift** — `rgba(<hue>, 0.42)` → `rgba(<hue>, 0.86)` and back. This makes the
   *highlighted text itself* the brightest thing on the page for ~1s.
2. **Focus ring + glow** — a `0 0 0 1.6px <solidSwatch>` outline plus a `0 0 16px 3px <hue>` outer
   glow, applied with `box-decoration-break: clone` so it traces every line-fragment of a wrapping
   passage (not a single bounding rect). The ring carries the "locate" semantics; the glow gives it
   air on dark themes where translucent washes are dim.

Resting state is identical to today's persisted highlight (`inset 0 -1px 0 rgba(0,0,0,0.04)`), so the
settle is seamless — the bloom dissolves *into* the highlight that was already there.

---

## 3. Motion spec

```
t = 0ms      land. wash + ring at resting (== persisted). nothing yet.
t = 0–140ms  RISE. wash 0.42→0.86; ring 0→1.6px; glow 0→16px.  ease-out  cubic-bezier(0.22,1,0.36,1)
t = 140–360  HOLD. peak sustained (perceptual dwell so the eye catches it).
t = 360–1500 DECAY. wash 0.86→0.42; ring + glow → 0.            ease-in-out
t = 1500     settled == persisted. layer torn down.
```

- **Single fire.** Re-firing only on a *new* navigation (new `landingHighlightID` or a repeated tap
  on the same row, via an incrementing nonce). Never loops on its own.
- **Interruptible.** Any tap, page-turn, or scroll during the bloom cancels it immediately to
  resting — the user has clearly already found it.
- The canvas renders the curve as four frozen keyframes (rest → peak → mid-decay → settled) plus a
  looping live preview so the feel is legible without re-navigating.

---

## 4. Off-screen at landing — scroll-to-prominent

A saved range can land clipped: split across the page break, under the bottom chrome, or above the
first visible line. Blooming a half-visible highlight is worse than no cue.

- **Paged mode** — paginate to the page that contains the *whole* range and position the page so the
  range falls in the **reading band** (≈28–55% of the content height), not kissing an edge. Then bloom.
- **Scroll mode** — smooth-scroll the range to ~38% from the top of the content area, wait for the
  scroll to settle (`scrollEnd`), then bloom.
- If the range is genuinely taller than the band (a multi-line paragraph highlight), align its **first
  line** into the band so the bloom starts where the eye enters.
- Under Reduce-Motion the reposition is an **instant jump** (no smooth-scroll), followed by the
  static-hold fallback (§5).

This is the part most readers get subtly wrong — landing the target at the very top or bottom edge,
where it's technically on-screen but easy to miss. The band keeps it where the eye already is.

---

## 5. Reduce-Motion fallback

`@media (prefers-reduced-motion: reduce)` — and the in-app *Reduce Motion* setting — swap the bloom for
a **static hold**:

- Wash snaps to peak (0.86) with a solid `0 0 0 1.6px <solidSwatch>` outline. No glow spread, no scale.
- Holds for ~1.2s.
- A single **opacity** cross-fade (≈320ms) returns it to resting. No transform, no looping, no glow.

Opacity-only fades are permitted under reduced-motion; the spirit of the setting (no vestibular
movement) is honoured because nothing translates, scales, or spreads. The cue is still unmistakable —
the target is briefly the brightest, outlined thing on the page.

---

## 6. Across the five themes

The wash + ring + glow must read on **Paper, Sepia** (light family) and **Dark, OLED, Photo** (dark
family). Two theme-dependent knobs:

| Knob | Light family | Dark family |
|---|---|---|
| Glow alpha | `<hue> @ 0.55` (soft, the cream sheet is already bright) | `<hue> @ 0.85` (the dim washes need a brighter halo to read) |
| Ring | solid swatch, 1.6px | solid swatch, 1.6px (unchanged — the solid swatch is the same crisp colour on both) |

The **Photo** theme is the stress case (translucent dark sheet over an image). The solid-swatch ring +
brighter glow carry it — the ring never depends on the wash for legibility. Verified in the canvas
cross-theme matrix and across all four highlight colours.

---

## 7. What this does NOT cover

- The Notes/Highlights **list** UI itself (the row you tap) — unchanged; that's `vreader-annotations.jsx`.
- A "jumped here" **toast / banner** — rejected. A chrome toast pulls the eye *off* the page to read a
  label; the whole point is to draw the eye *to* the passage. The in-text bloom is the message.
- **EPUB / Foliate** renderer — the issue scopes TXT/MD first. The bloom is renderer-agnostic in
  principle (it only needs the range's client rects), but the EPUB wiring lands later per the parent.
- **PDF** highlight landing — PDFs anchor by quad-points, not text ranges; same bloom visual, separate
  geometry path, out of scope here.

---

## 8. Cross-references

| File | Role |
|---|---|
| `VReader Highlight Landing Canvas.html` | Canvas of every state across themes. Source of truth. |
| `highlight-landing-artboards.jsx` | `ReaderFrame`, `LocateBloom` (live), `landingStyle` (frozen keyframes), candidate treatments, spec card. |
| `vreader-reader.jsx` | `handleNavigateToLocator` sets `landingHighlightID`; `Segments` renders the transient layer. |

### Production wiring

- `ReaderViewModel.landingHighlight` becomes `{ id, nonce }` published state, set by
  `handleNavigateToLocator` and cleared on the next user interaction.
- `HighlightableTextView.setHighlightRanges(persisted:active:landing:)` gains a **third** range
  argument that is *not* deduped against `persisted` — it renders the bloom layer on top of the
  persisted wash. This is the one-line fix for the no-op the issue describes.
- The bloom timing lives in a single `LocateBloom` token bag (rise/hold/decay durations, peak alpha,
  glow radius) so the curve is tuned in one place, mirroring the `reader-navigation.md` ribbon token.
