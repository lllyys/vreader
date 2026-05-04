---
branch: fix/issue-223-epub3-nav-titles
threadId: 019df2ed-bdc1-74f0-a2b9-8eae7984a34f
rounds: 1
final_verdict: ship-as-is
date: 2026-05-04
---

# Codex audit log — fix/issue-223-epub3-nav-titles

Bug #104 fix: hoist nav.xhtml + NCX extraction out of the background `Task.detached` so `extractNavTitles` finds the file synchronously on first open.

## Round 1

**Findings**: none.

**Verdict**: **Ship as-is.**

Codex's notes:

- **Synchronous extraction order is correct.** `zip.extractEntry` does sync `Data.write(to:)` before returning. After both optional nav/NCX extracts finish, `extractNavTitles` calls sync `Data(contentsOf:)`. Within one parser instance, the ordering is now race-free.
- **Performance acceptable.** Two small extracts (nav.xhtml typically <5 KB, NCX similar) on the open path. Pessimistic ~200 KB total still low-single-digit milliseconds, well below WKWebView startup cost.
- **Concurrency unchanged.** Cross-instance cache-write race that existed pre-fix (multiple parser instances opening the same EPUB cache dir) is unchanged. Fix doesn't make it worse.
- **`try?` swallowing acceptable.** Failure → graceful degradation to "Section N", same as books without nav today.
- **Backward compat clean.** `capturedNavHref`, `capturedNcxHref`, `capturedOpfDirRel` are gone from the detached task; nothing else referenced them.

**Follow-ups Codex suggested (not blockers)**:
- NCX-only EPUB 2 end-to-end test
- Nav/NCX in OPF subdirectory (e.g., `OEBPS/nav.xhtml`)
- Both nav and NCX present (nav-wins assertion)
- CJK title preservation end-to-end

These would broaden coverage but the existing test (`epub3NavTitlesExtracted`) is sufficient for the regression. Tracker-worthy for future polish.

## Files changed

- `vreader/Services/EPUB/EPUBParser.swift` — moved 12 lines: nav + NCX extraction now sync (in open path), CSS/fonts stay deferred (in Task.detached). Captures cleaned up.
- `docs/bugs.md` — row #104 status flip to FIXED.

## Test coverage

`EPUBNavTOCTests` suite (4 tests) all pass:
- `epub3NavTitlesExtracted` — was RED, now GREEN (regression test)
- `fallbackToSectionNumberWithoutNav` — unchanged
- `withResolvedTitlesAppliesNavTitles` — unchanged (always passed; was the unit test that gave a false positive of "fix shipped")
- `cjkTitlesPreserved` — unchanged

## What still might bite us

The cross-instance cache-write race (two parser instances on same EPUB cache directory) remains. Pre-fix code had the same risk via Task.detached writes; post-fix it's via the synchronous open path. Neither uses a file lock. Would be a bigger refactor to address — out of scope.
