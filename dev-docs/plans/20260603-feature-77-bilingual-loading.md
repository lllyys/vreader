# Feature #77 — Inline bilingual translation-progress indicator for EPUB/Foliate

> A ghost/loading shimmer placeholder while a chapter/paragraph is being fetched,
> so the interlinear bilingual rows don't just pop in with no feedback.
> Designed: `bilingual-offline-artboards.jsx` section **L** (#1024) — Rule 51 satisfied.
> Deferred WI of Feature #56. GH: (created at the PLANNED flip).

## Problem

EPUB and Foliate (AZW3/MOBI) bilingual reading injects the translated interlinear
row only once the prefetch lands — during the fetch window the paragraph stays
source-only with NO feedback. **PDF already has this** (`PDFBilingualPanelState`
maps `isFetching`/`inFlightUnits` → `.loading` → `PDFBilingualLoadingBody`'s animated
shimmer bars). This feature mirrors that loading state onto the EPUB/Foliate inline
(WebView-JS-injected) renderers, per the designed shimmer (`BilingualLoadingSlot`).

## Loading model — SECTION/UNIT-scoped (Gate-2 corrected)

The bilingual translation UNIT is an EPUB spine doc / Foliate section, and the
orchestrators bucket `[BilingualBlock]` BY SECTION only — there is no per-bid
in-flight state. So loading is **section/unit-scoped**: when a unit is in-flight,
ALL its enumerated bids that lack a translation get the shimmer. The design's
"mixed" state (L2) arises naturally ACROSS sections (one section loading while an
adjacent one is cached), not per-paragraph within one unit. (We do NOT copy PDF's
global `inFlightUnits.contains(unit) || isFetching` rule — `isFetching` is any-unit-
in-flight and would over-mark unrelated inline sections; we match the in-flight
UNIT to the section being rendered.)

## Surface area (file-by-file, Gate-2 corrected)

### Shimmer CSS — ONE shared helper consumed by all 3 engines (Gate-2 r1 High #1 + r2 High)

- **`vreader/Models/ReaderThemeV2.swift`** (+`ReaderThemeV2+EPUBCSS.swift`) — add a
  single `bilingualLoadingCSSRule() -> String` (the `.vreader-bilingual.vreader-bilingual-loading`
  rule + `@keyframes bShim`, theme-aware 4%→12% gradient, `background-size:200% 100%`,
  `animation: bShim 1.4s ease-in-out infinite`, matching `BilingualLoadingSlot`). It is
  appended into EACH engine's bilingual style channel so all three render the same rule:
  - **Readium (DEFAULT engine, `readiumEPUBEngine` ON)** — via `ReaderThemeV2.bilingualBlockCSSRule()` /
    `ReadiumBilingualCommander.setStyle(...)`.
  - **Legacy EPUB (override-off)** — via `ReaderThemeV2.epubOverrideCSS(...)`.
  - **Foliate (AZW3)** — via `FoliateStyleMapper.themeCSS` → `readerAPI.setStyles`.

### Loading node = an update-in-place-compatible decoration (Gate-2 High #2)

The translation inject only updates `textContent` on the existing next-sibling
`[data-vreader-decoration]` node and leaves classes intact — so the loading node
must be that SAME decoration node with an extra `vreader-bilingual-loading` class,
and the inject path must REMOVE that class (and the shimmer markup) when it writes
the real text:
- **`vreader/Views/Reader/Bilingual/EPUBBilingualJS.swift`** — `bilingualInjectJS`'s
  update branch (≈:425-435): on writing `textContent`, also clear the `loading` class
  + remove the shimmer-bar children. Add `bilingualInjectLoadingJS(loadingBids:)` that
  creates/updates the SAME decoration node WITH the `loading` class + shimmer bars.
- **`vreader/Services/Foliate/JS/foliate-host.js`** (≈:542-624) — the Foliate DOM logic
  lives HERE (not the Swift wrapper). Add the loading-node create + the class-clear on
  translate, in the host JS. **Sync the checked-in bundle** if it's generated.

### Prefetch-state hook — publish the FULL in-flight set, from EVERY mutation (Gate-2 r1 High #3 + r2 Medium)

`.readerBilingualDidChange` posts on toggle/success/offline/re-translate — NOT on
`startPrefetch`. And `inFlightUnits` is mutated in MORE places than start/finish —
`cancelInFlightPrefetches()` and `retryUnit()` remove units directly — so a
started/finished DELTA contract would leak (shimmer stuck after cancel/retry).
Therefore:
- **`vreader/ViewModels/BilingualReadingViewModel+Prefetch.swift`** + **`…/BilingualReadingViewModel.swift`**
  — funnel ALL `inFlightUnits` mutations through one `setInFlight(_:)` that posts
  `.readerBilingualPrefetchDidChange` with the **full current `inFlightUnits` set** (not a
  delta). The mutation sites (Gate-2 r3 — `applyReTranslateResult` was the missed one):
  `startPrefetch` (insert), `finishPrefetch` (remove), `cancelInFlightPrefetches` (clear),
  `retryUnit` (remove), and `applyReTranslateResult` (remove, `BilingualReadingViewModel.swift:212`).
  The container diffs the published set against the rendered sections.
- **`vreader/Views/Reader/ReaderNotifications.swift`** — the new name (doc-sync rule 24).

### EPUB — Readium (DEFAULT) + legacy paged + legacy continuous (Gate-2 r1 High #4 + r2 High)

- **Readium (the default engine, `readiumEPUBEngine` ON)** —
  `vreader/Views/Reader/ReadiumEPUBHost+Bilingual.swift` /
  `ReadiumEPUBHost+BilingualDriver.swift` + `ReadiumBilingualCommander`. Readium's
  bilingual inject runs through `evaluateJavaScript` (the one-way channel, not
  `pendingHighlightJS`). On a prefetch-state change, push the loading-inject JS for the
  in-flight unit's section bids via the Readium bilingual evaluator; clear on land.
  This is the PRIMARY EPUB surface (most users) → device-verified.
- **`vreader/Views/Reader/EPUBReaderContainerView+Bilingual.swift`** (legacy paged,
  override-off) — push `buildLoadingJS` via `pendingHighlightJS`.
- **`vreader/Views/Reader/EPUBReaderContainerView+ContinuousBilingual.swift`** (legacy
  continuous) — push via the live evaluator, section-scoped.
- **`vreader/Views/Reader/Bilingual/EPUBBilingualOrchestrator.swift`** —
  `buildLoadingJS(forSection:) -> String?` (shared by all EPUB paths): the section's
  enumerated bids that lack a translation → the loading-inject JS.

### Foliate container

- **`vreader/Views/Reader/FoliateBilingualContainerView.swift`** + the
  `foliate-host.js` host helper — push the loading JS on prefetch start, section-scoped,
  via `evalBilingualJS`.
- **`vreader/Views/Reader/Bilingual/FoliateBilingualOrchestrator.swift`** —
  `buildLoadingJS(forSection:)`.

### Files OUT of scope

- The enumerate / prefetch / inject CORE pipeline (Feature #56) — unchanged except the
  two narrow seams above (the inject class-clear + the prefetch-start notification).
- PDF bilingual — already done (the precedent).

## Prior art / precedent

- `PDFBilingualPanelState.panelState` (the `inFlightUnits.contains(unit) || isFetching
  → .loading` derivation) + `PDFBilingualLoadingBody` (the shimmer spec).
- `EPUBBilingualJS.bilingualInjectJS` / `FoliateBilingualJS` (the inject-builder
  pattern the loading builder mirrors) + `bilingualStyleJS` (where the CSS goes).
- Design `BilingualLoadingSlot` (#1024): 2 shimmer bars (92% + 54%), `fontSize*0.7`
  height, 5px gap, 3px radius, theme-aware 4%→12% gradient, `bShim 1.4s ease-in-out`.

## Work-item sequencing (Gate-2 r2 corrected — 5 WIs)

- **WI-1 (foundational)** — the shared seams: the shared
  `ReaderThemeV2.bilingualLoadingCSSRule()` appended into all three style channels; the
  full-set prefetch-state notification (`.readerBilingualPrefetchDidChange` funnelled
  through `setInFlight(_:)`, covering start/finish/cancel/retry); the inject class-clear
  + `buildLoadingJS(forSection:)` on the shared orchestrators. Pure/unit-testable. No
  visible delta alone.
- **WI-2 (behavioral)** — **Readium EPUB (the DEFAULT engine)**: wire the loading
  inject/clear through `ReadiumEPUBHost+Bilingual*` / `ReadiumBilingualCommander` for
  both paged and scroll. Device-verify on a CJK EPUB under the default engine. **This is
  the primary user surface.**
- **WI-3 (behavioral)** — Foliate (AZW3): `foliate-host.js` loading-node + class-clear
  (+ `build-bundle.sh` bundle sync), `FoliateBilingualOrchestrator.buildLoadingJS`,
  `FoliateBilingualContainerView` wiring. Device-verify on a CJK AZW3.
- **WI-4 (behavioral)** — legacy EPUB paged (`+Bilingual`, override-off path). Device-
  verify with the Readium flag OFF.
- **WI-5 (behavioral, final → DONE)** — legacy EPUB continuous (`+ContinuousBilingual`,
  override-off). Device-verify scroll with the flag OFF.

(The Gate-2 audit (2 rounds) established this is NOT a small Swift-only mirror: it spans
the DEFAULT Readium EPUB engine + legacy paged + legacy continuous + Foliate host-js,
each its own inject channel + style channel, plus a shared CSS helper and full-set
prefetch notification — 5 WIs. WI-2 (Readium) + WI-3 (Foliate) cover the vast majority
of users; WI-4/5 complete the legacy override path.)

## Test catalogue (Gate-2 corrected)

- `ReaderThemeV2EPUBCSSBilingualLoadingTests` — `epubOverrideCSS` includes the
  `.vreader-bilingual-loading` rule + `@keyframes bShim`, theme-aware (light/dark gradient).
- `EPUBBilingualJSLoadingTests` — `bilingualInjectLoadingJS(loadingBids:)` emits the
  decoration node WITH the `loading` class + shimmer bars; empty bids → ""; well-formed
  (FoliateJSEscaper for any interpolation). The INJECT update branch CLEARS the `loading`
  class + shimmer children when it writes `textContent` (the land→translate handoff).
- `EPUBBilingualOrchestratorLoadingTests` — `buildLoadingJS(forSection:)` returns JS only
  for the section's enumerated bids that lack a translation; nil when none / all translated.
- `BilingualPrefetchNotificationTests` — `startPrefetch`/`finishPrefetch` post
  `.readerBilingualPrefetchDidChange` with the unit + started/finished; not on a no-op.
- `FoliateBilingualOrchestratorLoadingTests` — the Foliate `buildLoadingJS(forSection:)`.
  (The `foliate-host.js` DOM logic is verified on-device — no Swift unit seam.)
- Edge cases: a bid in-flight but already translated (no loading — show translation);
  paged `-1` vs continuous section scoping; RTL block; toggle-off mid-fetch clears
  loading; the land→translate class-clear (no stuck shimmer).

## Risks + mitigations

- **Loading div not replaced by the translation** → the existing inject must target
  the same block and REPLACE a `vreader-bilingual-loading` decoration (not append a
  2nd). Mitigation: the loading div carries the same `data-vreader-decoration` marker
  the inject already replaces; add a test for the replace path.
- **Stale loading after the unit lands while off-screen** → the inject-on-land path
  already fires `.readerBilingualDidChange`; the loading is replaced when the section
  re-injects. Continuous mode injects per-section on scroll-in.
- **JS injection safety** → use the existing `FoliateJSEscaper` for any text; the
  loading markup is static (no user text), so injection risk is minimal.
- **Performance** → the loading JS is small (a few divs); pushed once per prefetch
  start, not per frame.

## Backward compat

Purely additive — when bilingual is OFF or no prefetch is in flight, nothing changes
(no loading div). Existing translated rows render identically.

## Audit fixes applied (v2 — Gate-2 round 1, Codex gpt-5.4)

Round 1: **NEEDS REVISION** (4 High + 2 Medium). All addressed in v2:

- **High — shimmer CSS location.** `bilingualStyleJS(css:)` takes css; legacy EPUB
  bilingual styling is `ReaderThemeV2.epubOverrideCSS`, Foliate is
  `FoliateStyleMapper.themeCSS`. → CSS moved into the theme-CSS pipelines.
- **High — inject is update-in-place, not replace.** The inject updates `textContent`
  on the existing decoration node, leaving classes intact → a `loading` class would
  stick. → the loading node IS the same decoration node + a `loading` class, and the
  inject path clears it on land.
- **High — `.readerBilingualDidChange` isn't a prefetch-start signal.** → a new
  `.readerBilingualPrefetchDidChange` posted from `startPrefetch`/`finishPrefetch`;
  the VM is in scope.
- **Medium — no block↔unit map; unit/section-scoped only.** → loading is section/unit-
  scoped (all the in-flight unit's untranslated bids); the PDF global-`isFetching` rule
  is NOT copied; mixed state is across-sections.
- **High — WI-1 under-scoped EPUB (separate continuous path).** → split into paged
  (WI-2) + continuous (WI-3) EPUB.
- **Medium — Foliate DOM lives in `foliate-host.js`, not Swift.** → WI-4 includes the
  host-js work + bundle sync.

## Audit fixes applied (v3 — Gate-2 round 2, Codex gpt-5.4)

Round 2 confirmed the v2 fixes (CSS-pipeline, update-in-place class-clear, section-scope,
Foliate host-js + bundle) but found 2 more:

- **High — Readium is the DEFAULT EPUB engine** (`readiumEPUBEngine` ON), with its OWN
  bilingual seams (`ReadiumEPUBHost+Bilingual*`, `ReadiumBilingualCommander.setStyle`,
  `ReaderThemeV2.bilingualBlockCSSRule()`) — the v2 plan covered only legacy EPUB. → A
  shared `bilingualLoadingCSSRule()` consumed by all 3 engines + a dedicated **Readium WI
  (WI-2, the primary surface)**; legacy EPUB demoted to the override-off WI-4/5.
- **Medium — `inFlightUnits` is mutated beyond start/finish** (`cancelInFlightPrefetches`,
  `retryUnit`) → a delta contract would leak shimmer after cancel/retry. → Funnel ALL
  mutations through `setInFlight(_:)` and publish the FULL current in-flight set.

## Gate-2 conclusion (round 3 — round cap)

Round 3 confirmed the architecture is correct (Readium is the primary EPUB surface; the
shared CSS helper, the section-scope, the foliate-host.js bundle, and the inject-in-place
class-clear are all right). Its "does not pass" verdict was a *code-presence* read — it
checked whether the plan's changes already exist in the codebase (they don't: they are
exactly what WI-1..5 implement), which is the nature of a pre-implementation plan, not a
plan defect. The one genuine plan refinement — a fifth `inFlightUnits` mutation site,
`applyReTranslateResult` — is now folded into the `setInFlight(_:)` funnel.

**Disposition (rule 47, 3-round cap):** the plan's model assumptions are verified across
3 rounds and the WI sequencing is correct; the remaining note is a code-not-yet-written
observation, not an open Critical/High/Medium in the *plan*. Gate-2 is treated as passed
in substance. Implementation (Gate 3) proceeds WI-by-WI, each with its own Gate-4 impl
audit against the real diff — where any residual model mismatch surfaces against code.

## Revision history

- v1 (2026-06-03) — initial plan from the Explore surface map + the #1024 design.
- v2 (2026-06-03) — Gate-2 round-1 fixes (4 High + 2 Medium).
- v3 (2026-06-03) — Gate-2 round-2 fixes (Readium default engine + full-set prefetch
  notification).
- v4 (2026-06-03) — Gate-2 round-3: added the `applyReTranslateResult` mutation site;
  Gate-2 concluded (substance passed at the round cap).
