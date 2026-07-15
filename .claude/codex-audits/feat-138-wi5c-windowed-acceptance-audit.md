---
branch: feat/138-wi5c-windowed-acceptance
threadId: 019f64c8-56ed-75b1-985b-14ab2a6fd62b, 019f64d7-e31a-7d50-a597-4cc4a2293bc6
rounds: 2
final_verdict: ship-as-is
---

# Gate-4 audit — feature #138 WI-5c (windowed TXT paged reader acceptance matrix, test-only)

Auditor: Codex `gpt-5.5` / high, via `scripts/run-codex.sh` (rule 53). Two rounds.
Subject: `android/app/src/androidTest/kotlin/com/vreader/app/reader/TxtPagedWindowedAcceptanceConnectedTest.kt`
(new connected acceptance class; NO production code). Full logs:
`.reports/feat138-wi5c-audit.txt` (round 1), `.reports/feat138-wi5c-audit-r2.txt` (round 2).

## Round 1 — 5 findings (all addressed)

1. **`revealInSamePublication` self-referential on a live partial index** (High). The convergence
   poll compared `currentPage()` to `pageContaining(savedOffset)` on the live (possibly partial)
   index, so a transient clamped page could coincidentally match. **FIXED**: after convergence the
   test now `awaitFinalPageCount()`s and asserts against `pageContaining(savedOffset)` on the
   COMPLETE index (`landedOnComplete == resumePageOnComplete`, and the page is strictly inside the
   grown book).

2. **`positionSurvivesPagedScrollPaged` did not assert the Scroll leg restored position** (Medium).
   It only checked the paged body unmounted. **FIXED**: the Scroll leg now polls
   `firstVisibleChunkForTest() > 0` and asserts a forward chunk — proving the position genuinely
   carried into Scroll mode, not that Scroll merely opened at the top.

3. **render-cache proof was size-only** (Medium). **PARTIALLY ADDRESSED within the test-only
   write-set** — see "Accepted Low" below.

4. **`farScrubberJump` did not prove the target was unmeasured at jump time** (Medium). **FIXED**:
   the test captures the first published (partial) count AND where the far offset clamps on it in
   the publish-predicate's first-true moment, asserts the far offset clamps into the sealed region
   then (unmeasured beyond the frontier), and after completion asserts the target page grew beyond
   that first observed frontier (`expected > firstPartialFrontierPage`, `finalCount > firstPartialCount`).

5. **a raw `while` + `Thread.sleep` loop is not `compose.waitUntil`** (Low). **ACCEPTED** — this is
   an intentional NEGATIVE stability-hold ("the pager must STAY on the user's page for this window"),
   which `compose.waitUntil` cannot express (it only waits for a condition to BECOME true). It matches
   the committed `TxtPagedTapZonesConnectedTest` tap-hint precedent. Codex confirmed this in round 2.

## Round 2 — re-audit

Confirmed resolved: findings 1, 2, 4, 5. Two remaining raised:

- **A. render-cache append/reflow proof still weak (finding 3 continuation)** (Low, ACCEPTED). Codex
  notes `cacheAfterAppends in 1..8` + `lineMarkerVisible(1)` could pass even if an append wrongly
  cleared the cache (the visible page recomposes/refills immediately), and `cacheAfterReflow in 1..8`
  does not prove the OLD page-number cache was cleared. The precise fix Codex suggests — a
  `clearCount`/`missCount`/generation stat on `PagedRenderCache` — is **PRODUCTION code**, outside
  this lane's test-only write-set (brief: a needed new production seam is an escalation, not
  something to add here). **Strengthened within the available `size`/`pageCount` seams**: append
  survival is proven by page 0 STILL being served from the cache after the count grows
  (`lineMarkerVisible(1)` post-append); the reflow-clear is proven by asserting the reflow genuinely
  RE-PAGINATED (the COMPLETE count and/or the page-for-a-fixed-offset changed under the larger font)
  — and `renderCache.clear()` is called on EXACTLY that re-pagination path and NOWHERE else (a
  code-structure invariant), so the bounded rebuilt window after a proven re-pagination evidences the
  clear+repopulate. Append survival is additionally covered by WI-5b's
  `backgroundAppend_doesNotClearRenderCache`. Residual: a dedicated cache-stat seam would make this
  airtight — recorded as a **follow-up** (production, out of WI-5c scope).

- **B. `growingCount` did not prove growth happened AFTER the page snapshot** (Medium). **FIXED**:
  the test now captures `firstPublishedCount` in the publish predicate's first-true moment and
  asserts `finalCount > firstPublishedCount` (relative, not a hardcoded window) with the pager placed
  on page 1 — the windowing genuinely appended pages while the pager sat on page 1.

## Stability (not a Codex finding — lane self-verification)

The fixture (`resume-sample.txt`, 100 lines → ~13 pages) completes its background pass FAST, so
several acceptance timings are inherently racy against an emulator gesture. Hardened deterministically:
tap-hint marked SEEN so taps are page-turns; the "user took over" case moves off page 0 via the
programmatic seam (the reveal reliably wins an emulator-tap race, so a deterministic off-page-0 move
falsifies the reveal's land guard); deep-resume/position legs page against the COMPLETE index;
`awaitFinalPageCount` requires 12 stable reads (no inter-window false-settle); the far scrubber jump
re-issues until it lands (`requestScrollToPage` can settle short under load — a real scrubber
re-issues). Verified GREEN across multiple consecutive full-class runs on emulator-5554 (final: 3
consecutive 6/6, 0-fail runs).

## Verdict

**ship-as-is.** All Critical/High/Medium findings resolved. Two Low residuals accepted with rationale:
the negative stability-hold idiom (precedented), and the render-cache stat granularity (tightest fix
needs a production seam out of the test-only write-set — covered at the available granularity + a
code-structure invariant + WI-5b's append-survival test; a cache-stat seam is a named follow-up).
