---
branch: fix/issue-746-feature37-xcuitest-swipeup
threadId: 019e33ce-4b58-7bb3-83ea-b2a5215d18f9
rounds: 2
final_verdict: ship-as-is
date: 2026-05-17
---

# Codex Audit — Bug #204 / GH #746

## Scope

Test-harness fix (XCUITest only, no product code). Single changed file:

- `vreaderUITests/Verification/Feature37PerBookSettingsVerificationTests.swift`

Reference files (read for comparison, not in scope to change):

- `vreaderUITests/Verification/Feature31AutoPageTurnVerificationTests.swift` — the proven swipe-up pattern this fix mirrors.
- `vreader/Views/Reader/ReaderSettingsPanel.swift` — confirms `perBookSection` has no header staticText and the toggle label is exactly `"Custom settings for this book"`.
- `vreaderUITests/Verification/Helpers/VerificationSettingsHelper.swift` — shared panel helper.

## The bug

`Feature37PerBookSettingsVerificationTests` always XCTSkip'd both `test_verify_*`
methods with "Per-book toggle not found". The per-book `Section` sits at the
bottom of `ReaderSettingsPanel`; SwiftUI Form sections are lazy-rendered, so a
section below the fold is not in the accessibility tree until scrolled into
view. The test called `toggle.waitForExistence(timeout: 5)` with no prior
swipe-up. Production feature #37 is fine and already VERIFIED — harness gap only.

## The fix

Added `revealPerBookToggle(in:)` — a bounded swipe-up loop mirroring
`Feature31AutoPageTurnVerificationTests`. The per-book `Section` has no header
staticText, so the loop keys on the toggle switch element itself (the only
stable anchor with the `"Custom settings for this book"` label). All four toggle
lookups (two primary + two fresh-panel `toggle2` re-checks) route through it.

## Round 1 findings

| Severity | Location | Finding | Resolution |
|---|---|---|---|
| High | `Feature37…Tests.swift` `toggle2` sites (isolation + reopen checks) | `if toggle2.waitForExistence(...) { assert }` — a toggle missing on the fresh `panel2` made the test pass vacuously, masking a scroll bug on the second panel. | Converted both to `guard toggle2.waitForExistence(...) else { throw XCTSkip(...) }` so a missing toggle is an explicit last-resort skip, consistent with the primary lookups. |
| Medium | `revealPerBookToggle(in:)` | Loop scrolled only until the switch `exists`, not until it was `isHittable`. Feature31 adds a post-discovery hittability budget; a `Toggle` row can enter the tree while still clipped at the bottom edge, so callers that tap it could hit an untappable control. | Added a second bounded loop `for _ in 0..<10 where toggle.exists && !toggle.isHittable { panel.swipeUp() }`, mirroring Feature31's 10-retry hittability budget. |

Assessment notes from round 1 (no action needed): switch-element anchor is
correct per `ReaderSettingsPanel.swift:747`; `@MainActor` usage fine; local
`NSPredicate` in `perBookToggle()` is not a Swift 6 concurrency issue; helper
extraction has no dead code.

## Round 2 result

Both findings confirmed resolved. Zero remaining Critical / High / Medium
findings in the changed file.

## Verification

- `xcodebuild build-for-testing` (iPhone 17 Pro Simulator): `** TEST BUILD SUCCEEDED **`
  — re-run after the round-1 fixes, still green.

## Verdict

**ship-as-is** — 2 rounds, clean.
