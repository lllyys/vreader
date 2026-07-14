---
branch: feat/137-wi11-acceptance
threadId: 019f623c-20ff-7c11-b1be-71cd71915e15
rounds: 1
final_verdict: follow-up-recommended
---

# Gate-4 audit — feature #137 WI-11 (final acceptance + perf tests)

**Scope (TEST-ONLY lane — no production code touched):**
- `android/app/src/androidTest/kotlin/com/vreader/app/reader/PagedAcceptanceConnectedTest.kt`
- `android/app/src/androidTest/kotlin/com/vreader/app/reader/TxtPaginatorPerfBenchmark.kt`

**Auditor:** Codex (gpt-5.x) via `scripts/run-codex.sh` (rule 53), thread `019f623c-20ff-7c11-b1be-71cd71915e15`.
Raw transcript: `.reports/wi11-audit-r1.txt`.

## Round 1 — findings and resolutions

Auditor result: **0 Critical, 3 High, 3 Medium, 2 Low.** All High + Medium resolved in-code; both Low resolved. The
one remaining "issue" (real-book phase-1 latency is high) is a plan-anticipated windowed-measurement follow-up, NOT a
test defect — hence `follow-up-recommended`.

### High
1. **Peak memory was not actually measured** (sampled only after `index()` returned → retained heap, not peak).
   **Resolved:** added a background `MemorySampler` thread that polls used-heap delta + `Debug.MemoryInfo` PSS every
   ~20 ms WHILE `index()` runs, so the reported peak is the true in-pass peak (real-book run recorded 1449–1479
   samples/pass).
2. **Scroll→Paged→Scroll tolerance too tight** (`savedChunk-1..savedChunk`) — a page spans many one-line chunks, so a
   correct scroll-back can land several chunks before `savedChunk`.
   **Resolved:** widened to the defensible non-destructive contract `finalChunk in 1..savedChunk` (at or behind the
   saved chunk, never ahead, never reset to 0).
3. **`targetChunk = 12` may fit on page 0** (device-dependent).
   **Resolved:** scroll target moved to chunk 60 of the 100-line fixture so the containing page is non-zero on any
   emulator geometry; the paged reopen still first asserts `currentPage() > 0`.

### Medium
1. **This class proves only TXT + MD, not the 3rd format (EPUB).**
   **Resolved:** the class doc now states WI-11's Gate-5 invocation runs BOTH `PagedAcceptanceConnectedTest` (TXT/MD)
   AND `EpubPagedToggleConnectedTest` (EPUB — Readium WebView paginated-overflow + page-turn currentLocator advance +
   live toggle both ways). Both classes are run in this WI's connected gate (see HANDOFF test evidence).
2. **The Paged→Scroll→Paged `-2 pages` window was unexplained/loose.**
   **Resolved:** replaced with self-consistency (`currentPage == pageContaining(currentSourceOffset)`) + the
   non-destructive bound `restoredPage in 1..pageContaining(savedOffset)` (at or behind the original page, never ahead,
   never 0).
3. **Any readable file >1 MB was logged as the real book.**
   **Resolved:** `readRealBookOrNull()` now validates the exact real-book byte size (14,059,220 ± 1000) before labeling
   the run `real`; a truncated/unrelated file falls through to the deterministic synthetic fallback.

### Low
1. `medianMs >= 0` was always true → tightened to `> 0`.
2. `pageCount > 100` message overstated → the assertion is now `> 1` with a "multi-page index" message (the real run
   produced 30,695 pages; synthetic 12,877).

## Confirmed sound by the auditor
- All named `@VisibleForTesting` seams exist in the merged `TxtReaderActivity` (including `flushPagedPositionForTest`'s
  paged-only no-op — the scroll baseline uses `moveToState(CREATED)` + a `cachedOffset` poll instead).
- `compose.waitUntil` is used throughout (no bare `waitForIdle`); warm run excluded; median-of-3 sorted.
- `index()` is the real phase-1 boundary pass, off-main.
- The synthetic corpus is deterministic and correctly scaled; the TXT/MD toggle assertions are non-vacuous.

## Post-audit device correction (Gate-5 connected run)
The first connected run surfaced a real defect the JVM/compile could not: `awaitBodyText()` (waits for "Line 001")
timed out on the two position tests' cross-layout reopens, because the reader legitimately RESUMES to a forward
position where "Line 001" is off-screen. Fixed by adding a format-agnostic `awaitReaderUp()` (the always-present
`tts-read-aloud-entry` chrome tag, the `TxtPagedBilingualGateConnectedTest` precedent) for the resume reopens; re-ran
GREEN (4/4). Also raised the perf ceiling `MAX_RUN_MS` 60 s → 180 s: the REAL 14 MB CJK book measured ~95.9 s/run
(vs ~1.2 s synthetic), and the plan (§Perf-bound, §Risks-5) says record the real number + file a windowed-measurement
follow-up, NOT hard-fail on a tight threshold.

## Verdict
`follow-up-recommended` — all audit findings resolved; the real-book phase-1 latency (median 95.9 s, 30,695 pages,
peak PSS 296 MB / peak used-heap delta 24 MB) is a documented windowed-measurement perf follow-up (plan §Perf-bound),
not a shipping blocker for the test artifacts.
