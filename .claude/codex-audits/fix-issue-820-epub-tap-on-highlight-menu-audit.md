---
branch: fix/issue-820-epub-tap-on-highlight-menu
threadId: 019e34d6-0837-74b1-826c-facd5a898723
rounds: 1
final_verdict: ship-as-is
date: 2026-05-17
---

# Codex audit — issue #820 (Bug #211): EPUB tap-on-highlight wrong compareBoundaryPoints constant

## Scope

Files audited:

- `vreader/Views/Reader/EPUBHighlightJS.swift` — the fix: the WI-4
  tap-on-highlight `click`-listener hit-test changed
  `range.compareBoundaryPoints(Range.END_TO_START, probe)` →
  `Range.START_TO_END` for the end-boundary membership check, plus an
  explanatory comment.
- `vreaderTests/Views/Reader/EPUBHighlightTapBridgeTests.swift` —
  regression-guard test asserting the JS bundle uses the correct call
  expression.

## Round 1 — findings

**No findings.** Codex confirmed the fix is correct and complete:

- **Correctness** — per the WHATWG DOM spec / MDN, `START_TO_END`
  compares `this` range's END to the source range's START, which is
  exactly the comparison the end-boundary check needs. The pre-fix
  `END_TO_START` compared `range`'s start to `probe`'s end — the wrong
  side of both ranges. The membership predicate
  `startVsProbe <= 0 && endVsProbe >= 0` is now correct for every
  boundary case (tap exactly at `range.start`, exactly at `range.end`,
  mid-range, just outside either end).
- **Edge cases** — collapsed `probe` range (start == end) is handled
  correctly; overlapping highlights still resolve "most-recent wins"
  via the reverse registry walk; the `catch` swallowing
  `compareBoundaryPoints` exceptions is the right failure mode for a
  stale/cross-root `Range`.
- **Surrounding logic** — no other defect found in the click-listener
  hit-test (`EPUBHighlightJS.swift` lines ~254-313). Control flow is
  coherent.
- **Regression test** — the string-assertion guard is meaningful for
  this codebase: the JS is embedded as a Swift string with no
  JS-execution harness, so pinning the exact `compareBoundaryPoints(…)`
  call expression is the right lightweight guard, and it matches the
  repo's existing JS-bundle string-assertion strategy
  (`EPUBHighlightTapBridgeJSTests`). The assertions match the full call
  expression rather than the bare constant token, so the explanatory
  JS comment (which names the old `END_TO_START` constant on purpose)
  cannot satisfy or break the guard.

Residual gap noted by Codex (not a defect in this fix): there is still
no executable WebKit/JS test harness for the embedded listener, so
JS syntax/runtime regressions remain outside unit-test coverage. This
is a pre-existing, codebase-wide testing limitation.

## Verdict

**ship-as-is.** Round 1 clean — zero Critical/High/Medium/Low findings.
The one-constant fix is correct per the DOM spec, the membership logic
is sound across all boundary cases, and the regression test is an
appropriate guard for a JS-string-embedded defect.
