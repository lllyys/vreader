---
branch: feat/131-wi8-txt-host
threadId: 019f6012-ed0b-7f72-b16f-824944781e50
rounds: 2
final_verdict: follow-up-recommended
---

# Gate-4 Codex audit — feature #131 WI-8 (Android TxtReaderActivity bilingual interlinear host)

Independent Codex audit (author/auditor separation, rule 47/48) of the WI-8 host integration:
the TXT/MD bilingual interlinear render wired into `TxtReaderActivity` under the round-4 H2
one-lazy-item-per-chunk contract, the translation gesture-exclusion, the round-5/6 TTS
source-bounds visibility fix, the position-driven prefetch + real text-provider wiring, and the
first-enable setup sheet.

- **Round 1** (`scripts/run-codex.sh -e high`, session `019f5ffa-1f69-7e30-9708-b20962359f15`) —
  verdict **block-recommended**. Confirmed the lazy-index==chunk-index core correct; found 3 High
  + 2 Medium + 1 Low.
- **Round 2** (session `019f6012-ed0b-7f72-b16f-824944781e50`) — after fixes, verdict
  **follow-up-recommended**. All 3 High + Medium-1 verified RESOLVED; 2 residual Medium items are
  hardening/perf follow-ups, no blocking production-correctness defect.

## Round-1 findings and resolutions

| # | Sev | Finding | Resolution |
| --- | --- | --- | --- |
| H1 | High | A target-language change while enabled did not retrigger position prefetch (`snapshotFlow` on `firstVisibleItemIndex` doesn't re-emit) → the visible unit stayed untranslated until the user scrolled. | The position `LaunchedEffect` is now keyed ALSO on `bilingualState.targetLanguage.key`; on a language change the VM's `invalidate()` clears the current-unit anchor, so the re-launched effect's first `snapshotFlow` emission re-dispatches the CURRENT position immediately. |
| H2 | High | TTS auto-scroll visibility keyed only on `firstVisibleItemIndex`, so scrolling WITHIN a tall source+translation item (index unchanged, offset changed) left the spoken source off-screen. | The TTS effect is now keyed ALSO on `listState.firstVisibleItemScrollOffset`. |
| H3 | High | Two eager whole-document paragraph scans on the main thread on EVERY TXT/MD open, even while bilingual disabled (`TxtChapterTextProvider` ctor + `BilingualTxtAnchors`). | `LazyTxtChapterTextProvider` defers the provider's construction+scan to the first unit-resolving call; `BilingualTxtAnchors.byChunk` is now a `lazy` val (first `unitsForChunk`, only while enabled+rendering). A disabled / non-bilingual open now pays ZERO segmentation cost. |
| M1 | Medium | Gesture-exclusion bounds incomplete/stale: only the first slot per chunk reported bounds; a source-only/language-changed slot left a phantom rect. | `translationSlotBounds` is now keyed by `(chunkIndex, slotIndex)`; EVERY rendered slot reports its own rect with per-slot `DisposableEffect` disposal, and a source-only/empty slot proactively removes its rect. |
| M2 | Medium | Connected coverage didn't exercise the claimed invariants. | Added: a connected position-round-trip-with-bilingual-ON test; a TTS source-visibility seam test (scroll a chunk off-viewport → `isSourceChunkInViewport(0)==false`, top chunk `==true`); a LAID-OUT controller exclusion test proving `setExcludedBounds` bypasses `hitAt`'s nearest-chunk fallback vs a selecting baseline (the round-2 hardening moves the press-point BELOW the source so the fallback is genuinely reached). |
| L1 | Low | Connected test file slightly over ~300 lines. | Accepted — it is a test file (softer bar); staging helpers stay local for readability. |

## Round-2 residual findings (ACCEPTED — follow-up, not blocking)

1. **Medium (perf) — first-enable double main-thread scan.** On the FIRST enable, the lazy provider
   and the lazy anchors each run one paragraph scan (two scans of the same document). Sharing one
   off-main span index would require reshaping the read-only `TxtChapterTextProvider` (out of WI-8's
   write-set). Documented as a follow-up in `LazyTxtChapterTextProvider.kt`. The disabled/non-bilingual
   open — the common hot path — is already zero-cost.
2. **Medium (test completeness) — remaining gaps.** The TTS test does not construct the exact
   "same tall item, source above viewport, translation visible" pixel condition (it drives the seam
   via `scrollToItem`), and the position test uses a single-paragraph fixture with no interlinear
   items before the target (no test asset can be added within WI-8's write-set). The exclusion test's
   round-2 hardening addressed its half of this finding (the fallback is now genuinely reached). The
   remaining two are follow-up test-completeness items, not correctness gaps.

## Confirmed invariants (round 2)

- `items(count = document.chunkCount, key = { it })` loop + keys UNCHANGED → lazy-index==chunk-index
  preserved (position-save / every jump / TTS all correct); source `Text` byte-unchanged as the
  first `Column` child, translations as non-registered sibling children.
- `BilingualTxtAnchors` matches `TxtChapterTextProvider`'s paragraph segmenter, window size, ceiling
  division, kind, and window IDs (asserted by a connected parity test).
- `isSourceChunkInViewport` treats absent/detached/pre-layout coordinates as not-visible (safe → scroll).
- The bilingual VM is hosted in the Activity `ViewModelStore`; `BilingualServices` passes the same
  provider instance to the VM resolver and the prefetcher.

## Test result

All connected suites GREEN (0 flake), each run in its own invocation (rule 52, ANDROID_SERIAL=emulator-5554):
- `TxtReaderBilingualConnectedTest` — 8/8
- `TxtSelectionExclusionTest` — 3/3
- `TxtReaderBilingualGestureTest` (flaky long-press class, own invocation) — 1/1

`RUN-ANDROID-TESTS RESULT: SUCCEEDED` for each.
