---
branch: fix/134-theme-test-setcontent
threadId: 019f515b-3dde-7ae1-a2b9-69ed8c3e87dd
rounds: 1
final_verdict: ship-as-is
date: 2026-07-11
tool: codex (scripts/run-codex.sh)
scope: test-only (androidTest Kotlin) — feature #134 Gate-5 follow-up
---

# Gate-4 audit — #134 `rendersAcrossThemes` Compose test fix

## Context

Feature #134's Gate-5 acceptance verifier found two connected suites RED due to a
test-authoring bug shipped in the merged WI-3 (`MorePopupTest`) and WI-4
(`BookDetailsSheetTest`): both `rendersAcrossThemes` tests looped
`compose.setContent { … }` inside `for (theme in ReaderTheme.values())`.
`AndroidComposeTestRule.setContent` may be called only ONCE per test, so the
second iteration threw `IllegalStateException: … has already set content`. No
product defect — every acceptance-relevant test in both suites passed; the
product itself verified end-to-end on real EPUB + TXT books.

## Fix

- `BookDetailsSheetTest.rendersAcrossThemes`: render every theme in ONE
  `setContent` via a `Column` of `BookDetailsSheetContent(theme = …)`, then assert
  `onAllNodesWithTag("book-details-sheet-content").assertCountEquals(ReaderTheme.values().size)`.
- `MorePopupTest.rendersAcrossThemes`: single `setContent` with the theme driven
  by `mutableStateOf`; the loop mutates the state and asserts `more-popup` exists
  per theme (popup-safe — avoids stacking multiple popup windows).

Production code untouched; two `androidTest` files only.

## Verdict — ship-as-is (Codex, 1 round)

Codex (thread `019f515b-3dde-7ae1-a2b9-69ed8c3e87dd`) confirmed:
- Both tests now call `setContent` exactly once — the `IllegalStateException` is eliminated.
- Coverage is NOT weakened: `BookDetailsSheetTest` composes one sheet per theme and
  asserts the exact node count == enum size (exercises every theme); `MorePopupTest`
  recomposes per theme with a synchronizing semantics assertion each iteration.
- Only the two `androidTest` files changed; no production/config touched.
- No new flakiness (no timers/animations/async/repeated content installation).

## Green evidence

Both suites re-run connected on `emulator-5554` after the fix:
- `com.vreader.app.reader.details.BookDetailsSheetTest` — 14 tests / 0 failures / 0 errors / 0 skipped.
- `com.vreader.app.reader.more.MorePopupTest` — 11 tests / 0 failures / 0 errors / 0 skipped.

Raw Codex transcript: `.reports/testfix-audit.txt` (lane-local, not committed).
