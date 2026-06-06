---
branch: fix/issue-1542-chunked-bloom
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-06-06
---

# Gate-4 audit — Bug #322 (GH #1542): wire the locate bloom into the chunked TXT reader

Mirrors the feature-#74 WI-2 bloom trigger from `TXTTextViewBridge` into
`TXTChunkedReaderBridge` so chaptered-TXT-in-scroll (the chunked / UITableView
path — the large-CJK-novel case) blooms on a Notes/Highlights row tap.

## Manual fallback — why

The independent Codex auditor (`scripts/run-codex.sh`) wedged at 0% CPU during
the file-read phase (rule-53 ghost; killed, no findings emitted) — the same wedge
class seen on this large codebase earlier this session. Per rule 47, manual
fallback with evidence below.

## Manual Audit Evidence

**Files read**: `TXTChunkedReaderBridge.swift` (the new `landingBloomTarget`
static, `scheduleLandingBloomIfNeeded`, the `updateUIView` hook, the cancel sites),
`TXTChunkedHighlightHelper.swift` (the cancel helpers + the established
`chunkLocalHighlightRanges` clamp pattern the new mapping mirrors),
`TXTTextViewBridge.swift` (the reference trigger + the reused `landingTrigger` /
`bloomThemeFamily` statics), `HighlightableTextView.swift` (`playLandingBloom`),
`TXTChunkedReaderBridgeBloomTests.swift` (the 7 new tests).

**Verified**:
- The trigger reuses `TXTTextViewBridge.landingTrigger(highlightRange:persisted:)`
  (exact-range match against persisted highlights) + `bloomThemeFamily(for:)` — no
  duplication; a search hit (range that is NOT a persisted highlight) does not
  bloom (tested).
- The pure static `landingBloomTarget(matchedRange:chunkStartOffsets:)` resolves
  the chunk index (binary-search over `chunkStartOffsets`) + the chunk-local range
  (`matchedRange` shifted by `-chunkStartOffsets[chunkIndex]`); 7 tests pin chunk-0
  (unshifted), later-chunk shift, boundary, empty offsets → nil, zero-length → nil.
  Mirrors the clamping convention in the existing `chunkLocalHighlightRanges`.
- A separate `lastBloomNonce` (distinct from `lastHighlightNonce`) gates the bloom
  so a re-tap re-blooms without double-firing the temporary-highlight repaint.
- Interruptibility: a 0.35s cancellable `DispatchWorkItem` (so the navigate's
  programmatic scroll lays out the target chunk's cell first); cancelled by a
  superseding navigate, a content tap, a USER-driven scroll (a guard excludes the
  navigate's own programmatic scroll from self-cancelling), and `dismantleUIView`
  teardown (no leaked work item).
- @MainActor correctness (the coordinator is MainActor); no regression to the
  non-chunked path (it shares the statics, its code is untouched).

**Edge cases checked**: off-screen target chunk at fire time (the 0.35s settle +
the navigate scroll bring it on-screen; the `cellForRow` is re-resolved at fire
time, no-op if still nil — acceptable, bloom is best-effort visual); zero-length /
out-of-range mapping → nil (no bloom, tested).

**Tests** (re-run green): `TXTChunkedReaderBridgeBloomTests` (7),
`HighlightableTextViewTests` (19), `LandingBloomPaintTests` (6),
`TXTChunkedBridgeHighlightTapTests` (8), `TXTChunkedHighlightDeferredTimerTests`
(8), `TXTChunkedSearchHighlightClearTests` (12), `TXTContinuousHighlightTests` (5).
`** BUILD SUCCEEDED **`.

**e2e (the load-bearing verification, via the #74 CU-free harness)** — booted
iPhone 17 Pro Sim, Debug build of this branch:
```
# CHUNKED (war-and-peace, chaptered → TXTChunkedReaderBridge, "Chapter 1 of 4"):
reset → seed war-and-peace → open → highlight?start=300&end=420 → snapshot (count=0)
  → locate?highlight=0 → snapshot ⇒ landingBloomCount=1, peakIntensity=1.0   ✅ (was 0 pre-fix)
# NON-CHUNKED (bloom-sample, "Chapter 1 of 1" → TXTTextViewBridge):
  … landingBloomCount 0 → 1   ✅ (unchanged path, no regression)
```

**Risks accepted**: `TXTChunkedReaderBridge.swift` is ~1218 lines (over the ~300
guideline) but was already ~1135 pre-fix; a full Coordinator split is out of scope
for a focused bug fix (the two cancel helpers were relocated to the existing
`TXTChunkedHighlightHelper` extension). `ship-as-is`.
