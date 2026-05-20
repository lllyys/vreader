---
branch: fix/issue-1049-stale-f11-f64-xcuitests
threadId: 019e44cf-ad12-70c1-b810-805af5c1d749
rounds: 2
final_verdict: ship-as-is
date: 2026-05-20
---

# Codex Gate-4 Audit — Bug #240 / GH #1049

## Scope

Test-only change resolving Bug #240 in `docs/bugs.md` (mirror GH #1049):
`Feature11EPUBHighlightVerificationTests` + `Feature64TXTHighlightPopoverVerificationTests`
fail against post-feature-#60 chrome re-skin (broken reader-loaded gate)
and still use the pre-Bug-#237/#220 long-press gesture path that XCUITest
cannot reliably synthesize on iOS 26.

Files changed:
- `vreaderUITests/Verification/Feature11EPUBHighlightVerificationTests.swift`
- `vreaderUITests/Verification/Feature64TXTHighlightPopoverVerificationTests.swift`
- `docs/bugs.md` (row 240 → FIXED)

No production code (`vreader/...`) was modified.

## Round 1 — initial audit

Findings:

| File:Line | Severity | Issue | Fix |
|---|---|---|---|
| `Feature11EPUBHighlightVerificationTests.swift:196` and `Feature64TXTHighlightPopoverVerificationTests.swift:107` | Medium | `XCTSkipUnless(bridgeReachable())` treats any failed `settleApp` probe as "sandboxed runner / CoreSimulator XPC blocked", but the helper returns only a Bool and cannot distinguish that case from other real regressions (wrong `booted` simulator resolution, broken `vreader-debug://settle` handling, bad app-container lookup, simple 5s timeout). A genuine bridge regression could be silently converted into a skip with the wrong reason. | Reword skip reason to name both the dominant sandbox cause AND the alternative possibilities; do not assert sandbox unconditionally. |
| `Feature64TXTHighlightPopoverVerificationTests.swift:157` | Medium | Accepts either `highlightPopoverSheet` OR `highlightPopoverCard`, but native TXT contract (`hostViewProvider == { nil }`) mandates the sheet form. Accepting the card weakens the regression net — a future host-view-provider plumbing regression on TXT would pass silently. | Require `highlightPopoverSheet` only. Update comment to explain why the sheet is mandatory on native TXT. |
| `docs/bugs.md:637` | Low | Row still says `vreader-debug://highlight-create?...`, but the actual helper / tests use `vreader-debug://highlight?start=<int>&end=<int>[&color=<name>]`. Tracker note inaccurate. | Replace all `highlight-create` mentions with the real command grammar. |
| `Feature11EPUBHighlightVerificationTests.swift:1` | Low | File is 325 lines, over the repo's ~300-line guideline. | Trim historical inline-comment repetition into the file header. |

Resolution:
- Medium #1 — **fixed**: rewrote both `XCTSkipUnless` messages to "DebugBridge probe failed (most commonly: sandboxed XCUITest runner cannot reach CoreSimulatorService — NSPOSIX 61 'Connection refused'; could also indicate a real bridge or settle-handler regression)". Names both possibilities so a genuine regression isn't mis-labeled as a sandbox issue.
- Medium #2 — **fixed**: Feature64 now requires `highlightPopoverSheet` only. The `popoverCard` waiter + acceptance path removed. Comment updated to explain the `hostViewProvider == { nil }` contract mandates the sheet form on native TXT.
- Low #3 — **fixed (partial in R1)**: replaced the repro-paragraph mention of `highlight-create`. Two other mentions (title + fix-direction) remained — flagged in R2 and fixed there.
- Low #4 — **fixed**: trimmed redundant inline comments in `Feature11EPUBHighlightVerificationTests.swift`. Down from 325 → 298 lines, under the cap.

## Round 2 — re-verification

Findings:

| File:Line | Severity | Issue | Fix |
|---|---|---|---|
| `docs/bugs.md:637` | Low | Row only partially corrected in R1: repro paragraph uses new URL grammar, but the row title and "Fix direction" text still said "highlight-create commands" / "highlight-create command". | Rename both remaining `highlight-create` mentions. |

Resolution:
- Low — **fixed**: both remaining mentions in row 240's title + fix-direction text updated to `vreader-debug://highlight?...`. `grep -c "highlight-create" docs/bugs.md` now returns 0.

Verdict statement from Codex round 2: "Everything else from round 2 checks out. The skip messages are now accurate about ambiguity, the TXT test correctly requires `highlightPopoverSheet`, and the EPUB file is back under the size guideline at 298 lines. Verdict after fixing the remaining tracker wording: ship."

## Final verdict

**ship-as-is** — 0 open findings after R2.

## Test results post-audit

```
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test-without-building \
  -project vreader.xcodeproj -scheme vreader \
  -destination 'platform=iOS Simulator,id=1FAB9493-B97E-48F0-96C7-44A8E5AAA21E' \
  -parallel-testing-enabled NO \
  -only-testing:vreaderUITests/Feature11EPUBHighlightVerificationTests \
  -only-testing:vreaderUITests/Feature64TXTHighlightPopoverVerificationTests
```

Result: 3 tests, 3 skipped (with explicit Bug #240 reason), 0 failed.
The reader-loaded chrome gate (the feature-#60 re-skin regression net)
ran unconditionally and passed in all 3 cases.

Full unit gate (`xcodebuild test -only-testing:vreaderTests`): 6828 tests
in 682 suites passed in 37.1s.
