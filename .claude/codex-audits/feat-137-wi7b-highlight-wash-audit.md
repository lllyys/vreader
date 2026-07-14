---
branch: feat/137-wi7b-highlight-wash
threadId: 019f61fd-5c94-7cb3-a822-ee39c8688300
rounds: 1
final_verdict: ship-as-is
---

# Gate-4 audit — feature #137 WI-7b (Android paged highlight wash + host wiring)

Auditor: Codex (`gpt-5.6-sol`, read-only sandbox), thread `019f61fd-5c94-7cb3-a822-ee39c8688300`.
Rounds: 1. Final verdict: **ship-as-is** (zero Critical/High/Medium/Low findings).

## Scope audited

- `android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderBody.kt`
  - new `object TxtPagedWash.washesForPage(map, highlights)` — projects each stored highlight's
    SOURCE range to page-local rendered `WashSpan` via `PageOffsetMap.sourceRangeToRendered`
    (never `offsetForChunk`); page-boundary-spanning highlights clamp per page (each call sees only
    that page's map).
  - `TxtPagedBody` gains a `highlights` param; each page `Text` draws the per-page washes behind it
    via `drawBehind` + `drawWashes` (the scroll body's `getPathForRange` mechanism), keyed on
    `remember(pageMap, highlights)`; the layout is captured whenever selection OR wash needs it.
- `android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt`
  - wired `selectionController`, `onSelectionFinalized`, `onTapEditAt = onTxtTapEditPaged`, and
    `highlights = highlightsList` into the `TxtPagedBody` call site (deferred WI-7a wiring) so paged
    SELECTION (WI-7a) and paged WASH (this WI) are LIVE in-app, at parity with the scroll `TxtBody`.
  - new private `onTxtTapEditPaged(...) : Boolean` — resolves tap → source → hit-test → opens the
    edit popover and returns `true` iff a highlight was hit, so the unified `pagedTapZones` classifier
    suppresses page-turn/chrome navigation for that tap.
- Tests: `TxtPagedWashTest.kt` (JVM, 10 cases — range math incl. boundary-clamp + MD dual-affinity),
  `TxtPagedHighlightConnectedTest.kt` (connected, 6 cases — wash on a real page map, boundary-span on
  both pages, real render, real tap-to-edit fires + suppresses nav, non-highlight tap returns false,
  long-press still selects with wash wired).

## Audit points confirmed clean

1. Wash uses `PageOffsetMap.sourceRangeToRendered` ONLY — no `offsetForChunk`.
2. Page-spanning highlights are intersected + clamped independently per page map.
3. The paged host receives the SAME highlight state + selection controller as the scroll host
   (finalize + tap-to-edit callbacks included).
4. The scroll `TxtBody` branch is behaviorally unchanged.
5. Reflow clears `renderCache`, publishes a new index/map; `pageWashes` is keyed on `pageMap` +
   `highlights` (stale-highlight redraw correct).
6. `pageLayout` is Compose state → `drawBehind` invalidates when layout arrives; the live TXT/MD host
   always has a non-null controller so layout is captured even before highlights exist.
7. Tap-to-edit returns `true` only after resolving + opening an existing highlight — navigation
   correctly suppressed; a non-highlight tap returns `false` (navigates).

## Verdict

**ship-as-is.** No code changes required from the audit. (Audit was static; Gradle tests were run
separately by the lane: JVM `TxtPagedWashTest` 10/0; connected `TxtPagedHighlightConnectedTest` 6/0,
`TxtPagedSelectionConnectedTest` 8/0 no-regression, `TxtPagedBodyConnectedTest` 6/0 no-regression.)
