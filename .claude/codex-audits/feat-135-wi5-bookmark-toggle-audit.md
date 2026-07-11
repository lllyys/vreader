---
branch: feat/135-wi5-bookmark-toggle
threadId: 019f51da-e92e-76a3-a80d-fe21fd93f02d
rounds: 1
final_verdict: ship-as-is
date: 2026-07-11
---

# Gate-4 audit — feature #135 WI-5 (top-bar bookmark toggle + Bookmarks route + current-locator state)

Independent Codex audit (rule 53 `scripts/run-codex.sh`, read-only sandbox, model `gpt-5.6-sol`)
of the WI-5 diff (`git diff origin/main..HEAD`). Prompt focused on the four contract points:
(1) exhaustive-`when` completeness over `ReaderSheet` + Saver round-trip; (2) rule-51 fidelity of
`BookmarkToggleButton` vs `vreader-reader.jsx` + no invented Bookmarks-list; (3) #132 back-compat
(defaults + slot-absent-when-null); (4) params mirror the annotations/bookDetails pattern + no host
wiring leaked in.

## Scope audited

- NEW `reader/chrome/BookmarkToggleButton.kt` — the designed top-bar toggle.
- `reader/chrome/ReaderChromeState.kt` — `ReaderSheet.Bookmarks` + `token()`/`sheetFromToken()`/Saver.
- `reader/chrome/ReaderChromeScaffold.kt` — `isCurrentBookmarked`/`onToggleBookmark`/`currentLocator`
  params + built bookmark slot + `Bookmarks -> Unit` render branch.
- `reader/EpubReaderChrome.kt` — bookmark params on `EpubTopBand` + `Bookmarks` normalized-to-None
  guard + exhaustive-`when` branch in `EpubReaderSheets`.
- Tests: JVM `ReaderChromeStateSaverTest` (bookmarks round-trip + invalid→None); instrumented
  `BookmarkToggleButtonTest` + extended `ReaderChromeScaffoldTest`.

## Round 1 — verdict: ship-as-is (no blocking findings)

Codex confirmed:

- **Exhaustive-`when` completeness.** Every `when` over `ReaderSheet` (token codec, parser,
  `ReaderChromeScaffold`, `EpubReaderChrome`) includes the `Bookmarks` branch — no Kotlin
  hard-fail.
- **Saver.** Both visible/hidden `Bookmarks` states round-trip; unknown and malformed tokens
  safely restore to `None` (never a throw).
- **Rule 51.** `BookmarkToggleButton` matches the committed design (`vreader-reader.jsx`): 18dp
  filled/accent icon when bookmarked vs outline/ink when not, a 48dp touch target, and actionable
  accessibility content-descriptions that flip Add/Remove. NO WI-6 bookmark-list UI or placeholder
  invented.
- **Back-compat.** `onToggleBookmark` defaults to `null`; existing #132 Contents/Notes-only callers
  remain source-compatible and the slot is omitted when null.
- **Pattern parity.** The new params follow the existing nullable/defaulted annotations/book-details
  threading pattern; `currentLocator` is intentionally unused until WI-7.
- **No host wiring leaked.** The EPUB host remains unwired — defaults keep the toggle absent, so no
  WI-7 host behavior bled into WI-5.

Full transcript: `.reports/wi5-audit.txt` (session `019f51da-e92e-76a3-a80d-fe21fd93f02d`).

## Test gate

`RUN-ANDROID-TESTS RESULT: SUCCEEDED` — `:app:compileDebugKotlin` +
`:app:compileDebugAndroidTestKotlin` (both source sets, including the new instrumented tests) +
`:app:testDebugUnitTest --tests 'com.vreader.app.reader.chrome.*'` (JVM Saver suite: 15 tests, 0
failures). Live Compose instrumented run rides WI-9 (rule-55 lane gate: compile-only for
instrumented on this lane).
