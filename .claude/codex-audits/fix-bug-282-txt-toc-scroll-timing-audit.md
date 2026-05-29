---
branch: fix/bug-282-txt-toc-scroll-timing
bug: 282
gh_issue: 1259
gate: 4
auditor: codex (codex exec --sandbox read-only)
threadId: codex-exec-bug282-toc
rounds: 1
final_verdict: ship-as-is
date: 2026-05-29
---

# Gate-4 Codex audit — Bug #282 (GH #1259)

TXT TOC takes ~1.3s to scroll to the current chapter (retry-loop timing).

## Scope audited

Diff of:

- `vreader/Views/Reader/Annotations/TOCSheet.swift` — `.task(id:)` scroll loop rewrite.
- `vreader/Views/Reader/Annotations/TOCSheet+Support.swift` — new pure
  `scrollRetryDelaysMilliseconds = [0, 80, 240]`.
- `vreaderTests/Views/Reader/Annotations/TOCSheetTests.swift` — two new
  schedule-timing tests.

Prompt: `.claude/codex-audits/fix-bug-282-prompt.txt` (request: correctness of
immediate-jump + fallback ladder on long TOCs, cumulative-gap arithmetic,
no layout/design change per rule 51, no new flaky timing, `@MainActor`
concurrency, edge cases).

## Verdict

**ship-as-is** — no Critical / High / Medium / Low findings.

## Auditor notes (verbatim summary)

- **Correctness**: `[0, 80, 240]` is treated as cumulative delay. The loop
  sleeps 80ms before attempt 1 and 160ms more before attempt 2, so attempts
  occur at 0ms, 80ms, and 240ms total. Attempt 0 is unanimated.
- **Layout/design**: `ScrollViewReader { LazyVStack { ForEach ... } }` remains
  unchanged inside the existing outer `ScrollView`; behavior-only timing fix.
- **Cancellation/staleness**: `Task.isCancelled` is checked after each possible
  sleep and before each scroll. `.task(id: currentChapterScrollTarget)`
  cancels stale retries on locator/target change or sheet teardown.
- **Concurrency**: `proxy.scrollTo`, `withAnimation`, and `Task.sleep` are used
  appropriately in the SwiftUI task context; no new Swift 6 strict-concurrency
  hazard in this diff.
- **Edge cases**: `nil` target returns early; empty schedule no-ops;
  single-element schedule performs one attempt; a non-zero first element would
  sleep once then perform the first unanimated attempt — sane for the
  cumulative-delay contract.

## Test + build gate

- `xcodebuild test -only-testing:vreaderTests` (serial, iPhone 17 Pro,
  UDID 61149F0E-DC18-4BE2-BB37-52659F1F4F62): **7581 tests / 740 suites passed**
  (two earlier runs hit transient `Early unexpected exit ... never finished
  bootstrapping` simulator flakes — no failing test names — and passed cleanly
  on the third foreground run with no contending xcodebuild).
- `xcodebuild build`: **BUILD SUCCEEDED**.

tokens used: ~31.5k
