---
branch: fix/issue-225-highlighted-snippet-test
threadId: 019df300-7efe-7b63-b38e-2cee79509bce
rounds: 1
final_verdict: ship-as-is
date: 2026-05-04
---

# Codex audit log — fix/issue-225-highlighted-snippet-test

Bug #105 re-diagnosed: not a production bug, just an impossible test invariant. Test-only fix.

## Round 1

**Findings**: none.

**Verdict**: **Ship as-is.**

Codex confirmed the misdiagnosis: `NSRegularExpression.matches` returns non-overlapping matches at offsets 0 and 3 for "abcabc" + "abc"; the production code correctly appends two consecutive bold segments; `AttributedString.runs` reports attribute runs (not append boundaries), so adjacent segments with identical fonts coalesce into one run. Visible rendering is correct.

The replacement tests are well-shaped:

- `multipleNonAdjacentMatches_produceSeparateBoldRuns` — realistic FTS5-snippet case where plain text between matches prevents coalescing.
- `consecutiveAdjacentMatches_coalesceIntoOneBoldRun` — pins the coalescing invariant so future contributors don't repeat the investigation.

Codex's optional follow-up (not required to ship): a regex-semantics test for true overlapping patterns (e.g., "aba" in "ababab") to document NSRegularExpression's leftmost-first non-overlapping behavior. Separate from bug #105.

## Files changed

- `vreaderTests/Utils/HighlightedSnippetTests.swift` — replaced 1 broken test with 2 well-shaped tests.
- `docs/bugs.md` — row #105 status flip to FIXED with re-diagnosis note.

## Test coverage

15 tests in `HighlightedSnippetTests`, all green. New tests:
- `multipleNonAdjacentMatches_produceSeparateBoldRuns` — replaces the impossible-invariant test.
- `consecutiveAdjacentMatches_coalesceIntoOneBoldRun` — documents the coalescing behavior.
