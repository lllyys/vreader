# Feature #85 — Seamless Readium EPUB cross-chapter scroll (approach C)

**Status**: Gate 2 PASSED (3 rounds; round-3 Medium accepted + fix incorporated
per the 3-round cap) → Gate 3 (TDD)
**Row**: `docs/features.md` #85 (TODO)
**Author**: claude
**Date**: 2026-06-05
**Approach**: **C — Hybrid re-route** (user decision 2026-06-05): route Readium
EPUB *scroll* mode to the legacy #71 `EPUBContinuousScrollCoordinator`
single-column stitch; Readium keeps *paged*. (Approach A — fork Readium —
rejected as high-cost/fragile.)

---

## Problem

EPUB renders via the Readium engine by default (`readiumEPUBEngine` flag ON
since the WI-14 G2 flip). Readium's navigator is a **per-resource paginator**:
in *scroll* mode, reaching a chapter boundary auto-navigates to the next spine
resource, which reloads at its top through Readium's `PaginationView` — a
**visible resource-transition SEAM/jump** at every chapter boundary. Feature
#83 (auto-advance, Bug #309) made the advance automatic but documented +
accepted this seam as inherent to Readium's closed paginator (no stitch
injection point). #85's goal: **no jump at all** — a single continuous scroll
across chapters, matching the user's standing #180 directive ("boundary-swap is
the wrong model").

This is the EPUB analogue of #76 (AZW3 windowed scroll) and #71/#180 (TXT
continuous scroll). It is a **feature** (a rendering capability Readium scroll
mode never had), not a bug in #83.

---

## Key architecture finding (verified)

The legacy **#71 continuous-scroll stitch is fully built and operational** —
it just isn't *reached* when Readium is the default engine:

- **Dispatcher** — `ReaderContainerView.engineReaderView()`
  (`ReaderContainerView.swift:1097-1118`) routes EPUB to `ReadiumEPUBHost`
  (flag ON) vs `EPUBReaderHost` (flag OFF) based on **only** the
  `readiumEPUBEngine` flag — NOT on layout.
- **Legacy stitch auto-activates** — `EPUBReaderContainerView.buildContinuousScrollConfig()`
  (`EPUBReaderContainerView.swift:552-553`) builds the `EPUBContinuousScrollCoordinator`
  window whenever `FeatureFlags.epubContinuousScroll` (default ON) AND
  `epubLayout == .scroll`. The coordinator stitches ±1-chapter sections into a
  single WKWebView DOM (no seam). It is mature (Feature #71, device-verified)
  with section-scoped bilingual (WI-7), windowed position (`onWindowedPosition`),
  per-section highlight restore (`onSectionMaterialized`), and search-nav
  (`coordinator.navigate(toSpineIndex:fraction:)`).

So **the seamless renderer already exists**; the headline change is **routing**
EPUB *scroll* mode to it while *paged* stays on Readium.

**BUT (Gate-2 round-1, MAJOR GAPS): the per-mode engine split is the hard part,
not the routing.** With approach C the SAME book is rendered by **two
different engines** depending on mode (legacy in scroll, Readium in paged), and
these engines do NOT share position or highlight state today:

- **Position is not cross-engine-restorable today.** Readium open restores
  ONLY a `.readium` envelope (`ReadiumEPUBReaderViewModel.swift:268`); legacy
  scroll clears `vreaderLocatorData` and writes its own legacy locator
  (`PersistenceActor+ReadingPosition.swift:50-58`). So a legacy-scroll session
  followed by a Readium (paged) reopen/toggle falls back to **book start** —
  for *normal* EPUBs, not edge cases. The only existing converter
  (`readiumLocator(fromVReader:spineHrefs:)`, `+Navigation.swift:45-70`) is
  legacy→Readium and is **not wired into restore**; the reverse doesn't exist.
  Worse, Readium's dual-write stores `readiumLocator.href.string` (container-
  relative `OEBPS/...`) into the legacy leg unchanged, so legacy's exact-match
  against OPF spine hrefs (`EPUBFileLoader.swift:59`) fails → href
  normalization is required.
- **Highlights don't transfer.** Readium-created highlights persist an `.epub`
  anchor with an EMPTY CFI/serialized range (`ReadiumSelectionHighlightBuilder.swift:69`);
  the legacy EPUB renderer paints ONLY from `serializedRange` JS
  (`EPUBHighlightActions.swift:22-55`) and never re-anchors from a text quote.
  A paged→scroll toggle therefore makes Readium-created highlights **disappear**
  in scroll mode. This is user-visible and "document it" is not acceptable.
- **The mode-toggle handoff is racy.** The outgoing host saves position in an
  UNAWAITED background `Task` on disappear (`ReadiumEPUBHost+Body.swift:228`,
  `ReaderFormatHosts.swift:188-206`) while the incoming host starts restoring
  immediately → a toggle can restore **stale** state. Routing-only is NOT
  independently shippable.

These make WI-1 (routing) and the position bridge **one inseparable slice**,
and add a real highlight-continuity WI. The plan below reflects that.

---

## Surface area

### In scope

#### WI-1 — Layout-aware dispatch + bidirectional position bridge + awaited handoff (one inseparable slice)

Routing alone is NOT shippable (Gate-2 Critical/High): it would strand position
on every cross-engine reopen/toggle. WI-1 is the smallest slice that delivers
the seam removal WITHOUT a position regression. Three coupled parts:

1. **Layout-aware dispatch helper** —
   `vreader/Views/Reader/ReaderContainerView.swift` (`engineReaderView`, ~1097)
   + a new pure `EPUBEngineRouter.resolve(readiumFlagEnabled:layout:) -> {readium,
   legacy}`. The helper **reads `settingsStore.epubLayout`** (it does not today
   — Gate-2 Low); once the branch reads it, `@Observable` re-evaluation on a
   mode toggle swaps the host. Truth table pinned by tests: flag ON + scroll →
   legacy; flag ON + paged → Readium; flag OFF → legacy (both).

2. **Bidirectional position-restore bridge** — the converter the plan needs
   does NOT exist (Gate-2 Critical). Add a restore bridge used by BOTH mounts:
   - **Legacy (scroll) mount** restores from whatever is persisted: if a
     `.readium` envelope is the latest, decode it → **normalize the
     container-relative href to OPF-relative** (Gate-2 High,
     `EPUBFileLoader.swift:59` exact-matches OPF hrefs) → legacy `Locator`
     (href + progression); else use the legacy locator directly.
   - **Readium (paged) mount** restores from whatever is persisted: if a legacy
     locator is the latest, convert via the EXISTING
     `readiumLocator(fromVReader:spineHrefs:)` (`+Navigation.swift:45-70`,
     currently unused for restore — wire it in); else the `.readium` envelope.
   - Persist a **single source-of-truth position** per book (engine-neutral
     href + progression) so neither engine clobbers the other
     (`PersistenceActor+ReadingPosition.swift:50-58` currently clears the cross
     field). Degrade to chapter-top ONLY for genuinely ambiguous hrefs.

3. **Awaited handoff on host swap** — the outgoing host saves in an unawaited
   `Task` (`ReadiumEPUBHost+Body.swift:228`, `ReaderFormatHosts.swift:188-206`)
   → racy stale restore (Gate-2 High). Hand off the **live locator in-memory**
   at toggle time (the dispatcher captures the current position before the swap
   and seeds the incoming host), OR gate the swap on an awaited save flush.
   In-memory handoff is preferred (no disk round-trip, no race).

**Acceptance (WI-1)**: EPUB scroll renders via the #71 stitch (no seam); open +
scroll↔paged toggle preserve position to the same chapter+fraction for normal
EPUBs (no book-start fallback).

#### WI-2 — Cross-engine highlight continuity (real renderer, not a doc note)

Gate-2 High: Readium-created highlights persist with an EMPTY CFI/serialized
range (`ReadiumSelectionHighlightBuilder.swift:69,77`); the legacy EPUB renderer
paints ONLY from `serializedRange` JS (`EPUBHighlightActions.swift:22-55`), so
they vanish in scroll-via-legacy. "Document it" is rejected — and (Gate-2 round
2) **dual-anchor-on-create alone is insufficient** because it leaves every
ALREADY-persisted Readium highlight invisible.

**Mandatory (not optional): a SECTION-SCOPED quote-to-Range re-anchor for
empty-`serializedRange` EPUB highlight records.** When a record's
`serializedRange` is empty, re-anchor by the persisted **text-quote + context**
(the data Readium DOES persist — `PersistenceActor+Highlights.swift:29`,
`Locator.swift:41`). Gate-2 round-3 precision (a page-global find-and-wrap is
wrong — it can match the wrong stitched section and bypass tap/delete):
- **Scope the quote search to the target href/section** — hook into the
  section-scoped restore path (`EPUBHighlightActions.restoreHighlightsInSectionJS`
  via `EPUBReaderContainerView`), NOT a document-global search, so a stitched
  multi-chapter DOM resolves the quote in the RIGHT chapter.
- **Exclude `data-vreader-decoration` bilingual nodes** from the quote match so
  the re-anchor doesn't land inside injected translation blocks.
- **Resolve to a real DOM `Range` and apply it through the EXISTING pipeline**
  (`applyHighlightRange` / `__vreader_createHighlight(InSection)` /
  `__vreader_highlightRanges`) so tap-to-edit and delete keep working — do NOT
  hand-roll a separate DOM wrapper that bypasses the highlight machinery.
This paints BOTH pre-existing AND future Readium-created highlights in legacy
scroll (and paged) with no migration/backfill (the records already carry the
quote). Persistence (`HighlightCoordinator`) is already engine-agnostic. Create
(the designed selection popover) is shared.

Optional add-on (NOT a substitute): dual-anchor-on-create (also compute a
legacy DOM range when a highlight is created in Readium) can make subsequent
paints exact rather than quote-matched — but the mandatory quote re-anchor is
what makes the feature correct for existing data.

#### WI-3 — Bilingual / TTS / search continuity + final acceptance

- **Bilingual**: the legacy continuous-scroll path already has section-scoped
  bilingual (#71 WI-7); `EPUBBilingualOrchestrator` is engine-agnostic. Verify
  coherence under async section stitching + a mid-read mode toggle.
- **TTS follow** + **search-nav**: both observe the posted `Locator` /
  `.readerNavigateToLocator`; the legacy coordinator already posts windowed
  position + handles nav. Verify parity in scroll-via-legacy. Final acceptance
  pass (Gate 5b) → row `DONE`/`VERIFIED`.

### Files OUT of scope

- **`ReadiumEPUBHost` paged mode** — unchanged; Readium stays the paged engine.
- **`EPUBContinuousScrollCoordinator` + #71 stitch internals** — reused as-is;
  not modified (they're mature + device-verified).
- **The `readiumEPUBEngine` flag semantics** — unchanged; approach C layers a
  layout check on top, it does not flip the flag.
- **Forking/patching vendored Readium** — explicitly rejected (approach A).
- **Feature #83's Readium continuous-scroll observer** — becomes dead weight in
  scroll mode (scroll no longer uses Readium); left in place (paged doesn't run
  it). A later cleanup WI may remove it, out of scope here.

---

## Prior art / project precedent / rejected alternatives

- **#71 (TXT/EPUB legacy continuous scroll)** — the stitch this re-routes to;
  device-verified, mature, section-scoped bilingual + windowed position.
- **#83 (Readium auto-advance)** — established that Readium scroll's seam is
  inherent (no stitch injection point); its plan documented approach C as the
  escalation fallback. #85 executes that fallback.
- **#76 (AZW3 windowed scroll) / #73 (Foliate continuous scroll)** — the
  format-analogues; both chose in-engine windowing because those engines (unlike
  Readium) had an injection point. Readium does not → re-route instead.
- **Rejected — approach A (fork Readium's `PaginationView` to stitch)**: a
  vendored-engine fork to maintain across Readium upgrades; rejected in #83's
  plan as high-cost/fragile. User confirmed C over A (2026-06-05).
- **Rejected — making BOTH modes legacy** (drop Readium entirely): loses the
  Readium paged engine's parity work (WI-13 acceptance); approach C keeps
  Readium where it has no seam (paged).

---

## Work-item sequencing

- **WI-1 — dispatch + bidirectional position bridge + awaited handoff** —
  *behavioral*. The smallest INSEPARABLE shippable slice (Gate-2: routing alone
  strands position). Delivers the seam removal AND position continuity. Larger
  than a routing change: the position bridge (href-normalized, bidirectional,
  single source-of-truth) + in-memory handoff are real work. Device-visual:
  scroll across a chapter boundary → no jump; toggle preserves position. Minor.
- **WI-2 — cross-engine highlight continuity** — *behavioral*. **Mandatory**
  quote-based legacy re-anchor for empty-`serializedRange` records (covers
  pre-existing AND future Readium highlights — no backfill). Unit-test the
  re-anchor; device-verify a paged→scroll toggle keeps highlights visible.
- **WI-3 — bilingual / TTS / search continuity + final acceptance** —
  *behavioral, FINAL WI*. Verify each in scroll-via-legacy; full acceptance
  pass → row `DONE` → `VERIFIED`.

Estimated 3 WIs but **Medium-Large** (the Gate-2 findings turned WI-1 from a
one-line route into a position-bridging slice, and WI-2 into a real renderer).
This is a vendored-engine-adjacent state-bridging feature, not a quick re-route.

---

## Test catalogue

- `EPUBEngineRouterTests` (new) — truth table: (readiumFlag ON/OFF) × (layout
  scroll/paged) → engine. Pins: flag ON + scroll → legacy; flag ON + paged →
  Readium; flag OFF → legacy (both); the existing flag-only behavior for paged
  is preserved.
- Position round-trip tests — a saved Readium-stamped locator resolves to the
  correct href + progression for the legacy engine (and the reverse), or
  degrades to chapter-top deterministically.
- Continuity integration tests — bilingual section coherence under async
  stitch; TTS observes the windowed position; search-nav lands the right
  chapter+fraction in scroll-via-legacy.
- **Device-visual (Gate 5)** — scroll across ≥2 chapter boundaries on a real
  EPUB: confirm a single continuous scroll, **no resource-transition jump**;
  scroll↔paged toggle preserves position; highlights/bilingual survive per the
  WI-3 policy.

---

## Risks + mitigations

| Risk | Likelihood | Mitigation |
|---|---|---|
| **Cross-engine position restore is broken today** — legacy scroll clears the Readium envelope + writes its own; a Readium reopen/toggle falls back to book start (NORMAL EPUBs) (Gate-2 **Critical**) | Certain without the bridge | **WI-1 core**: single engine-neutral source-of-truth position (href+progression) + a bidirectional restore bridge wired into BOTH mounts; in-memory handoff at toggle. Not a footnote — it's the slice. |
| **Readium href is container-relative**; legacy exact-matches OPF hrefs → degrade hits normal books (Gate-2 **High**) | High | **WI-1**: normalize href to OPF-relative on the legacy restore leg; reserve chapter-top for truly ambiguous hrefs. |
| **Readium-created highlights vanish in scroll-via-legacy** (empty CFI/range, legacy paints only from `serializedRange`); dual-anchor-on-create alone misses pre-existing records (Gate-2 **High**, r1+r2) | High (user-visible) | **WI-2**: MANDATORY quote-based legacy re-anchor for empty-range records — covers existing + future (the quote is already persisted). NOT documentable-away; dual-anchor is an optional add-on, not a substitute. |
| **Mode-toggle handoff is racy** — outgoing host saves in an unawaited Task; incoming restores immediately → stale state (Gate-2 **High**) | High | **WI-1**: in-memory live-locator handoff at toggle, or await the save flush before the host swap. Why WI-1 can't be routing-only. |
| **Bilingual cache incoherence under async section stitch** | Low | The legacy path serializes materialization (`isExtending`) + fires `onSectionMaterialized` per section; WI-3 integration-tests a mid-read toggle + navigate. |

---

## Backward compat

- **No schema/persistence change** — positions + highlights persist in the same
  records; only which engine *renders* scroll changes.
- **Existing readers**: a book open in Readium scroll today re-renders via the
  legacy stitch on next open (seamless). Paged readers see no change.
- **The `readiumEPUBEngine` override OFF** (legacy for both modes) is unchanged
  — those users already get the legacy stitch in scroll.
- **Rule 51**: no new UI surface — same reader chrome, same scroll/paged toggle;
  approach C changes only the renderer behind scroll mode (eliminating a visible
  jump = restoring the intended seamless behavior). The seamless-scroll surface
  is the already-shipped #71/#180 continuous-scroll experience, now reached for
  Readium-default books. N/A.

---

## Revision history

- **v1 (2026-06-05)** — initial plan (approach C). Architecture verified against
  `ReaderContainerView.swift:1097-1118` (dispatcher) + `EPUBReaderContainerView.swift:552-553`
  (legacy stitch auto-build). Gate-2 round 1 (Codex `019e9571`, `gpt-5.4`/high)
  → **MAJOR GAPS**: 1 Critical + 3 High + 1 Low.
- **v2 (2026-06-05)** — addresses all round-1 findings:
  - **Critical (cross-engine position restore broken)** → WI-1 now includes a
    bidirectional position-restore bridge + a single engine-neutral
    source-of-truth position; not a "degrade gracefully" footnote.
  - **High (href container-relative vs OPF)** → WI-1 normalizes the href on the
    legacy restore leg.
  - **High (highlights vanish)** → WI-2 is now a real quote-based renderer /
    dual-anchor, NOT a documented limitation.
  - **High (racy unawaited handoff)** → WI-1 does an in-memory live-locator
    handoff at toggle; routing-only is explicitly NOT shippable.
  - **Low (`@Observable` claim)** → corrected: the dispatch helper must READ
    `epubLayout` (it doesn't today) for the toggle to re-evaluate.
  WI-1 + position bridge merged into one inseparable slice. Feature re-scoped
  Medium→Medium-Large. Gate-2 round 2 (Codex `019e9579`) → **NEEDS REVISION**:
  Critical + 2 High resolved (position bridge, href normalization, racy
  handoff); 1 High remained — WI-2 still permitted dual-anchor-on-create-only,
  which misses pre-existing Readium highlights.
- **v3 (2026-06-05)** — addresses the round-2 High: WI-2's quote-based legacy
  re-anchor for empty-`serializedRange` records is now **mandatory** (covers
  pre-existing AND future highlights from the already-persisted quote; no
  backfill); dual-anchor-on-create demoted to an optional add-on.
- **v4 (2026-06-05)** — Gate-2 round 3 (Codex `019e957f`) confirmed the round-2
  High RESOLVED (records carry the quote) and raised **one new Medium**: a
  page-global find-and-wrap is too loose for the stitched DOM. Per rule 47's
  3-round cap, **accepted + incorporated the auditor's exact fix**: WI-2's
  re-anchor is now SECTION-SCOPED (`restoreHighlightsInSectionJS`), excludes
  `data-vreader-decoration` bilingual nodes, and applies the resolved DOM Range
  through the EXISTING `applyHighlightRange` / `__vreader_createHighlight(InSection)`
  pipeline (preserving tap/delete). **Gate 2 PASSES**: Critical + all 4 High +
  the round-3 Medium all resolved; no unresolved findings — no user escalation
  needed (the cap's escalation is for UNresolved findings; this Medium had a
  deterministic auditor-specified fix).
