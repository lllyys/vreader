---
branch: feat/138-wi2-sealed-partial-index
threadId: 019f63d8-962f-7091-82c2-67ec97ff6f18
rounds: 1
final_verdict: ship-as-is
---

# Gate-4 audit — feature #138 WI-2 (sealed-partial TxtPageIndex)

Independent Codex audit (rule 53, `scripts/run-codex.sh`, model gpt-5.6-sol,
read-only sandbox). Full transcript: `.reports/wi2-audit-r1.txt`.

## Files audited

- `android/app/src/main/kotlin/com/vreader/app/reader/paged/TxtPageIndex.kt`
- `android/app/src/test/kotlin/com/vreader/app/reader/paged/TxtPageIndexPartialTest.kt`

## Round 1

### Findings

- **Medium — ctor permits a contradictory `isComplete=true` + explicit
  `frontierSourceOffset != docEndExclusive` state.** No existing call site
  constructs this, but the public API did not guarantee the stated invariant
  ("a complete index's last page ends at docEndExclusive"): a caller could pass
  `isComplete=true, frontierSourceOffset=70` and change complete-index behavior.
  **FIXED in-lane:** the resolved `frontierSourceOffset` property now FORCES
  `docEndExclusive` whenever `isComplete` is true (the explicit arg is ignored
  for a complete index), so a complete index can never change its last page's
  end — the Gate-4 invariant is now enforced structurally, not by convention.
  Two regression tests added (`completeIndex_ignoresExplicitFrontier_*`).

- **Low — "next sealed page's start" wording was misleading.** The frontier is
  the START of the next PENDING/unpublished page (which is not itself sealed);
  the LAST PUBLISHED page is what becomes sealed once its successor's start is
  known. **FIXED in-lane:** header + class KDoc + property docs reworded
  accordingly.

### Confirmed by the auditor

- `TxtPageIndex` remains IMMUTABLE and purely data-oriented — NO measuring logic
  added; `starts` defensively copied in and out.
- `pageEndExclusive(lastPublishedPage) == frontierSourceOffset` correct for a
  valid partial index.
- Default construction, empty document, single-page, and `degenerate()` remain
  complete + behaviorally unchanged; all existing call sites omit the new args.
- `pageContaining(0) == 0` holds for every non-degenerate construction.
- Complete indexes with the default frontier behave byte-for-byte as before.
- `Int.MIN_VALUE` is a safe sentinel under the non-negative UTF-16-offset
  contract — it can never collide with a legitimate frontier.

## Final verdict

Round-1 raw verdict was `follow-up-recommended`, contingent on enforcing the
complete/frontier invariant "before broader construction begins." That single
Medium (and the Low wording) were fixed in-lane in this same WI + covered by new
regression tests, and the JVM gate re-ran GREEN
(`TxtPageIndexPartialTest` 21/0 + existing `TxtPageIndexTest` 9/0). With the only
non-Confirmed finding resolved, the remaining state is **ship-as-is**.
