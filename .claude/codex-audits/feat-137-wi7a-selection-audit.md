---
branch: feat/137-wi7a-selection
threadId: 019f61e3-bdb8-7d52-9534-c3578d51dd3e
rounds: 2
final_verdict: ship-as-is
---

# Gate-4 audit — feature #137 WI-7a (Android paged text selection)

Auditor: Codex (gpt-5.6-sol, via `scripts/run-codex.sh`, rule 53). Author/auditor separation held
(implementer = Claude lane; auditor = a separate Codex process).

## Files audited

- `android/app/src/main/kotlin/com/vreader/app/reader/TxtSelectionController.kt` — page-scoped registry
  (`registerPage`/`unregisterPage`), `hitAtPaged`/`beginAtPaged`, paged branches in
  `beginAt`/`extendTo`/`resolveSourceOffset`/`selectionEndAnchorWindow`, `pageOwning` round-trip,
  `rectDistance`.
- `android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderBody.kt` — `TxtPagedBody` per-page
  register/unregister + `PageOffsetMap` surfaced from `renderPage`, `PagedRenderCache` now caches the
  `(AnnotatedString, PageOffsetMap)` pair, selection callbacks wired to the unified `pagedTapZones`.
- `android/app/src/main/kotlin/com/vreader/app/reader/paged/PagedTapZones.kt` — the unified
  `awaitEachGesture` classifier (tap-zones + swipe coexistence + long-press-drag selection).
- `android/app/src/androidTest/kotlin/com/vreader/app/reader/TxtPagedSelectionConnectedTest.kt` (new).

## Round 1 — thread `019f61d3-e94d-7203-8641-844c9c3f1fae` (`.reports/wi7a-audit-r1.txt`)

Findings (all addressed before round 2):

- **Critical** — paged selection and tap-zones were two independent nested pointer recognizers that
  raced (the long-press wait vs the tap-zone `detectTapGestures`) and a settled tap double-fired
  (`onTapAt` + a page-turn/chrome action). **Fixed**: folded selection + tap-zones into ONE
  `awaitEachGesture` classifier in `pagedTapZones`. A settled tap runs tap-to-edit first
  (`onTapForEdit` returns whether a highlight was hit → suppress navigation), else a zone action; a
  long-press starts selection (begin+drag+finalize) and never navigates; a swipe is handled by the pager.
- **High** — the paged nearest-hit fallback used vertical-only distance, so horizontally-arranged
  `HorizontalPager` pages were all distance-0 and an arbitrary page/map won. **Fixed**: `hitAtPaged`
  now uses full-rectangle `rectDistance` + an x-band-containment preference + a page-index tie-break.
- **Medium** — `selectionEndAnchorWindowPaged` fell back to the highest registered page when the owner
  was not laid out, mapping the source through an unrelated page → a false popover anchor. **Fixed**:
  returns `null` when no registered page OWNS the end (`pageOwning` round-trip proves ownership).
- **Medium** — the registration `LaunchedEffect` did not key on `selectionController` while disposal
  did → a controller swap would unregister but never re-register. **Fixed**: keyed on the controller.
- **Medium** — paged hit-testing did not check `LayoutCoordinates.isAttached` → a detached layout
  lingering between eviction and `onDispose` could be consulted / throw. **Fixed**: `hitAtPaged` and
  `pageOwning` filter `coords.isAttached` (and `hitAtPaged` also checks the lazyCoords are attached).
- **Low** — file size (`TxtSelectionController` 331, `TxtReaderBody` 665). Accepted (below).

## Round 2 — thread `019f61e3-bdb8-7d52-9534-c3578d51dd3e` (`.reports/wi7a-audit-r2.txt`)

**No new Critical / High / Medium findings.** The auditor confirmed every round-1 finding resolved and
independently verified: the one-classifier tap/long-press/swipe disambiguation is correct
(`withTimeoutOrNull` + `waitForUpOrCancellation`, the still-pressed check for long-press, `drag(down.id)`
continuing the same pointer stream, consuming the tap up so the pager does not snap back); the coordinate
space is correct (`lazyCoords` + the gesture both on the pager, pager-local → window → per-page `Text`);
and the nearest-page tie-break is deterministic.

Two round-2 Lows, both addressed / accepted:

- **Low (fixed)** — the file-header comments still described selection + tap-zones as separate
  recognizers. Updated the `TxtReaderBody.kt` + `PagedTapZones.kt` headers to describe the single
  unified classifier.
- **Low (accepted)** — file size: `TxtSelectionController.kt` = 331 lines, `TxtReaderBody.kt` = 665.
  Accepted with rationale: the WI-7a lane brief explicitly forbids a mid-lane file split (a split adds a
  file outside the plan's write-set + needs a structural regen), and `TxtReaderBody.kt` was already a
  large-but-cohesive file from WI-6a. Extracting `TxtPagedBody`/`PagedRenderCache` and the paged
  controller helpers into focused files is a named follow-up for a later WI.

## Verdict

`ship-as-is`. Zero open Critical/High/Medium after 2 rounds. Connected gate: `TxtPagedSelectionConnectedTest`
8/8, `TxtPagedTapZonesConnectedTest` 4/4 (navigation preserved after the classifier refactor),
`TxtPagedBodyConnectedTest` 6/6 (no WI-6a regression).
