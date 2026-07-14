---
branch: feat/137-wi4-paginator
threadId: 019f610a-d21c-7e21-bdc7-fd7f4630ef49
rounds: 2
final_verdict: ship-as-is
date: 2026-07-14
---

# Gate-4 audit — feature #137 WI-4 (paged TXT/MD core types)

Scope: the three new pure-Kotlin files under
`android/app/src/main/kotlin/com/vreader/app/reader/paged/` —
`TxtPageIndex.kt` (boundary IntArray), `PageOffsetMap.kt` (composed
span-preserving page map), `TxtPaginator.kt` (two-phase measured-line
pagination) — plus the JVM tests under
`android/app/src/test/kotlin/com/vreader/app/reader/paged/`.

Auditor: Codex `gpt-5.5` / reasoning high, via `scripts/run-codex.sh` (rule 53).
Author (Claude) ≠ auditor (Codex) — Gate-4 author/auditor separation held.

## Round 1 (verdict: block-recommended) — 2 High, 2 Medium, 1 Low

| file:line | severity | issue | fix |
| --- | --- | --- | --- |
| TxtPaginator.kt (phase-1 push) | High | MD inserted-glyph bullet can create duplicate page starts (`•` + its space both map to source `[0,2)`) → very narrow measured lines yield a zero-advance page, violating the forward-progress invariant | **FIXED** — central `tryStartPage(candidate)` with a STRICT-ADVANCE guard (`candidate > starts.last()`); a non-advancing candidate keeps the line on the current page (may overflow — the min-one-line trade). Regression: `mdBulletNarrowLines_noZeroAdvancePage`. |
| TxtPaginator.kt (`index`) | High | `index()` was off-main only "by contract" — a caller could run the whole-doc measure pass on Main | **FIXED** — `TxtPaginator(indexDispatcher: CoroutineDispatcher = Dispatchers.Default)`; `index()` wraps its whole body in `withContext(indexDispatcher)`. Regression: `index_runsOnInjectedDispatcher` (injects a test dispatcher). |
| TxtPaginator.kt (`index`) | Medium | a cancelled token could still return a result for the degenerate-box / empty-doc early returns (cancellation was checked after them) | **FIXED** — `checkCancelled(token)` is now the FIRST statement in `index()`. Regressions: `cancelledToken_degenerateBox_stillThrows`, `cancelledToken_emptyDoc_stillThrows`. |
| TxtPaginator.kt (`renderPage`) | Medium | `renderPage()` detected Markdown via `mapper is MarkdownChunkTextMapper` — a wrapper/decorator around a Markdown mapper would fall into the TXT identity branch and corrupt spans | **FIXED** — `renderPage()` + `pageSegmentFor()` take an explicit `isMarkdown: Boolean` (no `is` downcast). Regression: `renderPage_wrappedMarkdownMapper_stillBuildsMdSegments`. |
| TxtPageIndex.kt | Low | claimed immutability but exposed the mutable `IntArray` | **FIXED** — constructor defensively copies into a private `starts`; `pageStartsUtf16` now returns a copy; all reads go through `starts`. |

## Round 2 (verdict: ship-as-is) — clean

Re-audit confirmed every round-1 finding resolved and introduced NO new
Critical/High/Medium findings. Positive checks re-confirmed: `PageOffsetMap`'s
direct Markdown delegation is structurally correct for whole-chunk MD segments and
mid-chunk MD slices; oversized-chunk TXT mid-chunk splits tile the source
contiguously (no dropped source); UTF-16 offset handling is surrogate/CJK safe;
the degenerate box and the empty-doc case are distinct.

## Final verdict

**ship-as-is.** All Gate-4 findings resolved in 2 rounds; the fixes are each
covered by a new regression test. JVM suite (`com.vreader.app.reader.paged.*`):
43 tests, 0 failures via `scripts/run-android-tests.sh` →
`RUN-ANDROID-TESTS RESULT: SUCCEEDED`.
