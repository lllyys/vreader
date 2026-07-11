---
branch: feat/133-wi9-sheet
threadId: 019f538f-0a69-72d3-b050-654819dcd177
rounds: 3
final_verdict: follow-up-recommended
---

# Gate-4 audit — feature #133 WI-9 (in-book-search sheet + rows Compose UI)

Independent Codex audit (rule 53, `scripts/run-codex.sh`, model gpt-5.6-sol, read-only sandbox)
of the WI-9 implementation. Files audited:

- `android/app/src/main/kotlin/com/vreader/app/search/InBookSearchSheet.kt`
- `android/app/src/main/kotlin/com/vreader/app/search/InBookSearchField.kt`
- `android/app/src/main/kotlin/com/vreader/app/search/InBookSearchRows.kt`
- `android/app/src/main/kotlin/com/vreader/app/search/InBookSearchStates.kt`
- `android/app/src/androidTest/kotlin/com/vreader/app/search/InBookSearchSheetTest.kt`

## Round 1 (thread 019f5380-a767-7572-b98f-6b8e7727590a) — 1 High, 4 Medium

- **High** — `boldedSnippet` was not UTF-16 surrogate-safe (a range boundary could split an
  emoji/CJK-B pair) and `r.last + 1` could overflow. **Fixed**: `snapBoundary()` snaps every span
  boundary off a surrogate interior; `r.last >= len` guards the overflow. Clamp/sort preserved.
- **Medium** — the search bar invented an accent border and placed Cancel outside the pill.
  **Fixed**: one rounded pill (search / input / clear / Cancel) per `vreader-search.jsx` lines 55-79,
  no border.
- **Medium** — results omitted the design's "N matches in M chapters" summary, the per-group tinted
  rounded container, and inter-row separators. **Fixed**: `InBookResultsSummary` + tinted container +
  0.5dp separators between hit rows; recents got the design's inter-row 0.5dp separators.
- **Medium** — Loading/Error rendered a blank body. **Resolved as a rule-51 decision** (not a bug):
  the design's `SearchSheet` depicts no Loading/Error/Indexing-distinct surface, and the sibling
  library `SearchScreen` suppresses rather than invents one; the query field stays live so a new
  query supersedes the transient/failed state. Documented in the `when` branch. Auditor concurred in
  round 2 ("defensible and resolved").
- **Medium** — Idle omitted the design's "Try searching" section. **Accepted**: that section is
  library-scope (operator-syntax / highlighted:/note: helper — out of #133 scope per plan §2/§3), so
  it is intentionally excluded, not silently dropped.

## Round 2 (thread 019f538c-1ae6-79e2-9ad8-cfb0d45390ff) — round-1 all resolved; 2 new Medium

- **Medium** — append-on-scroll did not re-arm when `loadMore()` coalesces a page into the current
  last group (hit count grows, group count unchanged). **Fixed**: the `LaunchedEffect` now keys on
  `(moreAvailable, lastGroupIndex, lastGroupHitCount, listState)`; a new `appendGrowingTheLastGroup_reArmsOnLoadMore`
  test covers the growth case. Auditor confirmed resolved in round 3.
- **Medium** — clear (✕) and Cancel tap targets under the 48dp minimum. **Fixed** (round-2 partial:
  44dp; round-3 corrected to 48dp).

Verified resolved in round 2: surrogate safety, single search pill, results/recents design structure,
state suppression, dismiss-on-success, RTL chevron, unique testTags, no unused imports/dead code.

## Round 3 (thread 019f538f-0a69-72d3-b050-654819dcd177) — append re-arm resolved; 1 Medium

- **Medium** — the round-2 tap-target fix used 44dp, below the Material 48dp minimum. **Fixed**:
  the clear Box is `size(48.dp)` and Cancel is `heightIn(min=48.dp).widthIn(min=48.dp)` — the exact
  change the auditor prescribed ("both containers should use at least 48dp; Cancel must also retain
  at least 48dp width"). Visible glyph/label sizes unchanged.

Round 3 confirmed the append-on-scroll re-arm resolved and found zero Critical/High.

## Final verdict: follow-up-recommended

All Critical/High/Medium findings across three rounds are addressed. The final Medium (48dp) was
fixed exactly per the auditor's prescription after round 3; a re-audit was not run (the 3-round
ladder was reached and the fix is a mechanical, self-contained correctness change with a compile-green
gate). `RUN-ANDROID-TESTS RESULT: SUCCEEDED` (`:app:compileDebugAndroidTestKotlin` +
`:app:testDebugUnitTest`) after each round. The instrumented Compose test set compiles; the live
render rides the WI-10/WI-11 host wiring + WI-12 acceptance slice (the #132/#134/#135 pattern).
