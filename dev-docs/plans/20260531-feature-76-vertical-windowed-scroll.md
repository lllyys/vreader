# Feature #76 — Vertical-writing windowed continuous scroll (Foliate AZW3/MOBI)

**Reclassified from Bug #283 / GH #1260** (2026-05-31, per user direction) — the
remaining scope after Feature #73. #73 shipped a K=3 windowed continuous-scroll
surface for Foliate scrolled mode, but **gated it to horizontal writing**
(`paginator.js #ensureWindow:910` returns early when `this.#vertical`). For a
vertical-writing AZW3 (Chinese `vertical-rl`, common), scrolled mode still uses
the OLD per-section view-swap — i.e. the exact #283 chapter-boundary jump. The
windowing for vertical writing was **never implemented** (the code path is gated
out, not broken) → per AGENTS.md this is a feature, the vertical-axis sibling of
Feature #73.

## Problem

Feature #73's windowing coordinate math is **vertical-scroll-axis-only**:
`#elementScrollTop` (uses `top`), `#evictOutsideWindow`'s scroll compensation
(uses `getBoundingClientRect().height` + `container.scrollTop`),
`#windowedResolve`, and the mount/expand offset adjustments all assume the
content flows top→bottom and the container scrolls on `scrollTop`. Vertical-
writing (`writing-mode: vertical-rl`) flows in columns and **scrolls on the
horizontal axis** (`scrollLeft`, right→left). So the windowing math doesn't
apply, and `#ensureWindow` is gated `if (… || this.#vertical) return`, leaving
all resolvers pointing at the single `#view` → per-section swap on crossing.

Plus: the Feature #73 Gate-2 **H7 large-CJK K=3 memory gate was never run** —
windowing 3 sections of a large CJK book could blow memory; this feature must run
that gate on a real device.

## Scope

In scope: generalize the windowing coordinate math over the **scroll axis**
(vertical-scroll vs horizontal-scroll) so K=3 windowing works for vertical-
writing AZW3/MOBI; remove the `!#vertical` gates once axis-aware; run the
large-CJK memory gate.

Out of scope: EPUB (separate engine — Feature #75 covers EPUB direction);
horizontal-RTL Foliate (the windowing for horizontal-RTL already works via the
vertical-scroll axis since RTL horizontal writing still scrolls vertically in
scrolled mode — confirm in WI-0); paged mode.

## Keystone — an explicit `ScrollModel` + a single canonical logical-offset API

Two distinct problems, both surfaced by the Gate-2 audit:

### (a) Preserve `writing-mode` — `{vertical, rtl}` is lossy (Gate-2 High)

`getDirection` (`paginator.js:178`) returns only `{ vertical, rtl }`, DISCARDING
the actual `writingMode` — so `vertical-rl` vs `vertical-lr` is lost (there is
even a live `FIXME: vertical-rl only, not -lr` in `#scrollTo`). The axis sign
CANNOT be inferred from `{vertical, rtl}`. So WI-1 derives and stores an explicit
**`ScrollModel`** per loaded section:

```
ScrollModel = { axis: 'vertical'|'horizontal',
                scrollProp: 'scrollTop'|'scrollLeft',
                sizeProp:   'height'|'width',
                rectStartProp: 'top'|'left',
                directionSign: +1 | -1 }   // -1 ⇒ WebKit RTL/vertical-rl negative scrollLeft
```

| writing mode | axis | scrollProp | sizeProp | rectStart | sign |
|---|---|---|---|---|---|
| horizontal LTR | vertical | scrollTop | height | top | +1 |
| horizontal RTL | vertical | scrollTop | height | top | +1 (scrolled mode scrolls vertically — WI-0 confirms) |
| vertical-rl | horizontal | scrollLeft | width | left | −1 |
| vertical-lr | horizontal | scrollLeft | width | left | +1 |

### (b) ONE canonical logical-offset API (Gate-2 Medium — avoid double-normalize)

Existing accessors already partly encode axis (`scrollProp`, `sideProp`, `start`,
`end`, `viewSize`, `page`, `pages`, `scrollBy`, `snap`) — some use
`Math.abs(scrollLeft)`, some apply the RTL sign later. A new helper that only
wraps the WINDOWED methods would double-normalize. So WI-1 defines ONE canonical
**logical scroll offset** (`#logicalScrollOffset` / `#setLogicalScrollOffset`,
always non-negative, reading-order) used by BOTH the existing accessors and the
windowed primitives, and audits every listed caller to route through it.

### (c) Layout strategy — `#container` must stack on the scroll axis (Gate-2 High)

Windowed insertion today only orders DOM children; `#container` block-stacks
vertically. Vertical-writing sections must accumulate **horizontally**. WI-2
makes `#container` an axis-aware stacking context (`display:flex` with
`flex-direction` = `column` (vertical-scroll) / `row` + RTL order
(horizontal-scroll)) BEFORE the `scrollLeft` math is relied on — this was a
required gate in Feature #73's own plan.

The pure Swift math (`FoliateScrolledWindowMath.swift`, 19 tests) generalizes its
offset/eviction functions to take the `ScrollModel`'s sign; the JS mirrors it.

## Surface area (file-by-file)

- **`vreader/Services/Foliate/JS/paginator.js`** (vendored, editable; bundled by
  `build-bundle.sh`):
  - `getDirection` (`:178`) → also return `writingMode`; build the `ScrollModel`.
  - New canonical `#logicalScrollOffset(el?)` / `#setLogicalScrollOffset(v)`
    (reading-order, non-negative) — **audit + route every existing axis-aware
    caller through it**: `scrollProp`, `sideProp`, `start`, `end`, `viewSize`,
    `page`, `pages`, `scrollBy`, `snap`, `#scrollTo` (the `FIXME: vertical-rl
    only`), plus the windowed primitives below. Tests cover raw negative
    `scrollLeft`, logical start/end, fraction emission, prev/next, snap, anchor.
  - `#elementScrollTop` (`:947`) → `#elementScrollOffset(el)` via `ScrollModel`.
  - `#evictOutsideWindow` (`:928`): compensation uses `sizeProp` + the logical
    offset (mirroring `height`+`scrollTop`), with `directionSign`.
  - `#onNeighbourExpand` (`:890`) — **explicitly in scope** (Gate-2 Medium): it's
    hardcoded height/top/scrollTop with NO `!#vertical` guard, so it WILL run for
    vertical once ungated; convert it to the `ScrollModel`/logical-offset helper.
  - `#windowedResolve` / `#viewRelativeStart` / mount paths: axis-aware.
  - Windowed `prev(distance)` / `next(distance)` / `#maybeCrossSectionBoundary`
    (`:1409,:1425`): replace hardcoded `scrollTop`/`scrollHeight`/`clientHeight`
    with the logical-offset + `sizeProp`, with RTL sign.
  - Remove the `this.#vertical` early-return in `#ensureWindow:910` and the
    `!this.#vertical` guards at `:1225,:1283,:1317,:1510` — replaced by
    ScrollModel branches (LTR vertical-scroll path byte-unchanged).
  - **`#container` layout** (WI-2): axis-aware `display:flex` stacking so vertical
    sections accumulate horizontally.
  - Rebuild `foliate-bundle.js`; `FoliatePaginatorScrollBoundaryTests` parity
    gate enforces source↔bundle sync.
- **`vreader/Services/Foliate/FoliateScrolledWindowMath.swift`** + its 19 tests:
  generalize the pure offset/eviction math to take a sign (the `ScrollModel`
  `directionSign`); existing vertical-scroll tests stay green (sign defaults +1).

### Files OUT of scope

EPUB readers; the Foliate paged path; the bilingual orchestrator.

## Prior art / precedent

- **Feature #73** is the direct precedent — same windowing engine, same
  mount/evict/resolve primitives, same `FoliateScrolledWindowMath` Swift seam,
  same `FoliatePaginatorScrollBoundaryTests` parity gate. This feature is its
  vertical-axis generalization.
- Foliate's own paginator already branches `side = this.#vertical ? 'height' :
  'width'` in the NON-windowed paths (`paginator.js:365,390`) — the axis pattern
  to mirror in the windowed paths.
- Bug #287's `FoliateTapToleranceBundleTests` is the precedent for pinning a
  JS contract in source + rebuilt bundle.

## Rejected alternatives

- **D2-only overlay polish** (mask the blank flash without windowing): the
  Feature #73 / Bug #283 assessment already rejected this — it leaves the D1
  content-swap visible and breaks the "one view in #container" invariant.
- **Keep the per-section swap for vertical, polish the swap**: doesn't clear the
  "no visible jump" bar (D1 is architecturally inherent to the swap).

## Work-item sequencing (revised after Gate-2 round 1)

- **WI-0** (confirm): (a) confirm horizontal-RTL Foliate scrolled mode uses the
  vertical-scroll axis (`#vertical==false` ⇒ `scrollProp=scrollTop`) so only
  vertical-WRITING needs the new horizontal axis — verify with an RTL horizontal
  fixture since rect/selection/nav paths still consume `#rtl`. (b) Determine
  whether the real `Bei Tao Yan De Yong Qi.azw3` is actually vertical-writing
  (probe its computed `writing-mode`); if not, a synthetic vertical-rl AZW3 is
  required for the behavior gate.
- **WI-1** (foundational): `getDirection` preserves `writingMode`; derive the
  `ScrollModel`; add the canonical `#logicalScrollOffset` API and **route every
  existing caller** (`scrollProp`/`sideProp`/`start`/`end`/`viewSize`/`page`/
  `pages`/`scrollBy`/`snap`/`#scrollTo`) through it — fixing the `vertical-rl
  only` FIXME. No windowing change yet; LTR + the existing non-windowed vertical
  paths stay behavior-identical. Pure `FoliateScrolledWindowMath` sign tests +
  JS logical-offset tests (raw negative scrollLeft → logical).
- **WI-2** (behavioral): `#container` axis-aware flex layout (vertical sections
  stack horizontally) — the layout gate BEFORE the windowed scroll math.
- **WI-3** (behavioral): make ALL windowed primitives ScrollModel-aware —
  `#elementScrollOffset`, `#evictOutsideWindow`, `#onNeighbourExpand`,
  `#windowedResolve`, windowed `prev`/`next`/`#maybeCrossSectionBoundary` — and
  remove the `!#vertical` gates. LTR vertical-scroll path byte-unchanged. Rebuild
  bundle; parity + new `FoliateVerticalWindowBundleTests` contract test.
- **WI-4** (behavioral, REGRESSION — Gate-2 Medium): re-run Feature #73's
  verified horizontal-AZW3 live acceptance after the axis abstraction — smooth
  crossing, K-window slide/evict, DOM order, Bug #265 restore — on `mini-azw3`
  (and the real AZW3). The shared windowing code changed, so #73 must be
  re-verified, not assumed.
- **WI-5** (behavioral): device-verify smooth crossing on a vertical-writing
  AZW3 (WI-0's real-or-synthetic fixture) — vertical-rl AND vertical-lr.
- **WI-6** (final, gating): the **large-CJK K=3 memory gate** (deferred Feature
  #73 H7), rigorously specified (Gate-2 Medium):
  - **Fixture**: a large vertical-writing AZW3. The repo's only AZW3
    (`Bei Tao Yan De Yong Qi` ~6MB) — confirm its writing-mode (WI-0); the large
    CJK EPUB/TXT fixtures CANNOT validate Foliate memory (different engine). If
    no large vertical AZW3 exists, **state the limitation**: the memory ceiling
    is validated on the largest available AZW3, and the vertical-behavior gate
    uses a synthetic — the memory *claim* is bounded by the real-book size.
  - **Measurement**: peak resident memory (`task_info` `phys_footprint` / RSS,
    sampled every 250 ms) over a single continuous scroll across **≥5 section
    boundaries** with K=3 windowing; record the max.
  - **Baseline**: the identical scroll with `#windowedScroll=false` (per-section
    swap); record its max RSS.
  - **Threshold (pre-declared, pass/fail BEFORE Gate 3)**: K=3 PASSES iff
    `peak_RSS(K=3) ≤ peak_RSS(baseline) + 120 MB` **AND**
    `peak_RSS(K=3) ≤ peak_RSS(baseline) × 2.0`. Rationale: K=3 mounts at most 2
    extra adjacent sections; 120 MB absolute headroom + a 2.0× relative cap bound
    both small and large books. If EITHER is exceeded → **fall back to K=2 for
    vertical** (re-run the gate at K=2; documented decision) rather than ship an
    OOM risk.

## Test catalogue

- `FoliateScrolledWindowMathTests` — extend the 19 existing with `directionSign`
  cases (eviction compensation, offset adjustment, resolve under −1).
- `FoliateVerticalWindowBundleTests` — pin the contract in source + rebuilt
  bundle: `getDirection` returns `writingMode`; no `!#vertical` early-return in
  `#ensureWindow`; `#onNeighbourExpand` routes through the logical-offset helper;
  the canonical `#logicalScrollOffset` exists.
- `FoliatePaginatorScrollBoundaryTests` — parity stays green.
- Device:
  - WI-4 — Feature #73 horizontal-AZW3 live regression (smooth crossing, slide,
    evict, DOM order, #265 restore).
  - WI-5 — vertical-writing AZW3 crossing (vertical-rl + vertical-lr).
  - WI-6 — large-CJK K=3 memory gate (RSS peak vs per-section baseline).
  via `scripts/sim-tap.sh` + `xcrun simctl` memory probe (live display — rAF
  caveat below).

## Risks + mitigations

- **rAF/scroll observers paused on virtual display** (documented memory
  `feedback_raf_observers_unverifiable_virtual_display`): the windowing slide is
  rAF-throttled, so the smooth-crossing assertion needs a REAL device / live
  display, not the cron virtual display. Mitigate: device verify via `sim-tap.sh`
  on a live simulator; inject the downstream `#ensureWindow` call directly for
  the CU-free contract check.
- **RTL horizontal scrollLeft sign** (WebKit negative convention) — same gotcha
  as Feature #75; pin with the pure-math sign tests + device check.
- **Memory** — the whole point of WI-4's gate; if K=3 is too heavy for large CJK,
  fall back to K=2 for vertical (documented decision).
- **Regression to horizontal windowing** (Feature #73, shipped + verified) — the
  LTR vertical-scroll path stays byte-unchanged; the full #73 suite + parity gate
  must stay green at every WI.

## Backward compat

Horizontal-writing AZW3/MOBI (the #73 path) is unaffected — axis defaults to
vertical-scroll. No persistence change.

## Audit fixes applied (Gate-2 round 1 → revision)

Codex `codex exec` plan audit round 1: NEEDS REVISION, 2 High + 5 Medium (all
model assumptions verified to exist). Revisions:

- **High — layout strategy**: added WI-2 — `#container` axis-aware `display:flex`
  so vertical sections stack horizontally (Feature #73's required layout gate),
  BEFORE the windowed scroll math.
- **High — writing-mode loss**: `getDirection` only returns `{vertical, rtl}`
  (vertical-rl vs -lr lost; live `FIXME`). WI-1 preserves `writingMode` + derives
  an explicit `ScrollModel {axis, scrollProp, sizeProp, rectStartProp,
  directionSign}`; sign is NOT inferred from `{vertical, rtl}`.
- **Medium — double-normalize**: one canonical `#logicalScrollOffset` API; WI-1
  audits + routes every existing axis caller (`scrollProp`/`sideProp`/`start`/
  `end`/`viewSize`/`page`/`pages`/`scrollBy`/`snap`/`#scrollTo`) through it.
- **Medium — `#onNeighbourExpand`**: now explicitly in WI-3 (it's unguarded and
  would run for vertical once ungated).
- **Medium — windowed prev/next**: WI-3 names the horizontal-axis replacement for
  `scrollTop`/`scrollHeight`/`clientHeight` + vertical-rl/-lr tests.
- **Medium — memory gate**: WI-6 now specifies fixture selection + writing-mode
  confirmation + measurement (RSS peak) + baseline (per-section swap) + threshold
  + the limitation that no large vertical AZW3 may exist.
- **Medium — #73 regression**: added WI-4 — mandatory horizontal-AZW3 live
  re-verification after the shared windowing code changes.

Round-2 re-audit: 6 of 7 resolved; 1 Medium open — memory threshold was not a
pre-declared numeric ceiling. Fixed: WI-6 now declares `K=3 ≤ baseline + 120 MB
AND ≤ baseline × 2.0`, else fall back to K=2.

## Status

Gate 1 + Gate 2 (round-2 revisions applied). Pending Gate-2 round-3 confirmation.
This is the deepest remaining feature (vendored-paginator.js writing-mode model
rework + layout + canonical offset API + memory gate); Gate 3 (TDD, 7 WIs) is a
dedicated focused phase.
