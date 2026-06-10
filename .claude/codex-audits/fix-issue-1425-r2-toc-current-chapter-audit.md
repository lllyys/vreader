---
branch: fix/issue-1425-r2-toc-current-chapter
threadId: 019eb370-36fa-72f0-b35a-6e02096d35b2
rounds: 2
final_verdict: ship-as-is
date: 2026-06-11
---

# Codex Gate-4 audit — Bug #313 round 2 (GH #1425 REOPENED): TOC current-chapter preceding-entry fallback

Runner: `scripts/run-codex.sh` (codex exec, gpt-5.4, read-only sandbox).
Sessions: r1 `019eb36c-3436-7d02-9782-8fac6406eb67`, r2
`019eb370-36fa-72f0-b35a-6e02096d35b2`.

## Round 1 — needs-fixes

| Finding | Severity | Resolution |
|---|---|---|
| `TOCSheetTests.swift:175` — the 6 new tests pinned the user repro + nil paths but not the string-identity edge cases the fix depends on (percent-encoded hrefs, duplicate entry hrefs, entries absent from `spineHrefs`); a one-sided href decode could regress with all tests green | Low | FIXED (6ddb77ba): `encodedHref_matchesOnlyIdenticalForm`, `duplicateEntryHrefs_lastWins`, `entryHrefAbsentFromSpine_isSkippedInFallback` |

Round 1 also POSITIVELY verified: the fallback ordering logic (last entry
with spine index ≤ current; exact wins; before-first/unknown → nil; ghost
entries ignored); the cross-engine href-space claim (legacy stitch posts
parser-space hrefs directly; Readium normalizes onto the same EPUBParser
spine via `ReadiumBilingualCommander.swift:182` / `ReadiumPositionBroadcast.swift:65`
/ `ReadiumEPUBHost+Body.swift:175`); the `buildTOC`/`buildTOCDetailed`
split preserves all callers and pdf/txt/md behavior; O(n·m) acceptable at
real TOC sizes.

## Round 2 — clean

All three prescribed tests confirmed in place and meaningful; "I do not
see a new regression or a newly introduced gap." VERDICT: clean.

## Summary

2 rounds, 1 finding (Low), fixed. `TOCSheetTests` green (incl. 9 new
tests modeling The Half Second's real cover-titled spine shape).
Device-verified pre-merge on The Half Second (legacy continuous-scroll
engine): prologue prose body → row 3 highlights; book toc page →
Copyright; exact cover match unchanged. Ship as-is.
