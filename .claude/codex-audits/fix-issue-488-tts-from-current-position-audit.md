---
branch: fix/issue-488-tts-from-current-position
threadId: 019e1376-0b90-7723-abe9-682218e675af
rounds: 3
final_verdict: ship-as-is
date: 2026-05-11
---

# Codex audit — bug #164 fix (TTS starts from article beginning instead of current visible position)

GH issue: #488. Severity: high.

## Root cause

Native TXT (`UITextView` path) was the only reader path NOT posting
`.readerPositionDidChange` on scroll. EPUB, MD, PDF, Foliate, and TXT-Unified
all post that notification on scroll/page change; TXT-Native was silent.
Result: `ReaderAICoordinator.currentLocator` stayed nil/stale, and
`ReaderContainerView+Sheets.swift:startTTS()` resolved
`let offset = ai.currentLocator?.charOffsetUTF16 ?? 0` to 0, so TTS always
started from offset 0 even after the user had scrolled mid-document.

## Files changed

Production:
- `vreader/ViewModels/TXTReaderViewModel.swift` — added private
  `broadcastPosition(_:)` helper that posts `.readerPositionDidChange`. Called
  unconditionally at the end of `open(...)`, end of `openChapterBased(...)`,
  and inside the success branch of `navigateToChapter(_:)`. Inside
  `updateScrollPosition(charOffsetUTF16:)` the call goes AFTER the existing
  post-restore-suppress check so storm-zero updates during the TextKit
  relayout settle window don't leak out.

Tests:
- `vreaderTests/Services/TXT/TXTReaderViewModelTests.swift` — new
  `TXTReaderViewModelPositionBroadcastTests` suite (5 tests):
  1. "updateScrollPosition posts readerPositionDidChange with current locator" — happy path
  2. "clamped negative offset still broadcasts (offset==0)" — edge: negative
  3. "clamped beyond-length offset broadcasts the clamped value" — edge: overflow
  4. "open with restored position seeds AI/TTS via post once" — restore-seed coverage with exact-count assertion
  5. "position broadcast suppressed during post-restore settling window" — suppress-then-post ordering

## Round 1 findings

| # | Severity | File:line | Issue | Resolution |
|---|---|---|---|---|
| 1 | Medium | `TXTReaderViewModel.swift:235`/`237` + `ReaderContainerView+Sheets.swift:27` | Restore-seed gap — after `open()` restores the position, the suppress window in `updateScrollPosition` drops storm-zero updates AND the legitimate restored offset. So `aiCoordinator.currentLocator` stays nil until the user scrolls past the suppress window — TTS started immediately after open would still resolve offset 0. | **Fixed**. Added `broadcastPosition(_:)` helper that bypasses the suppress logic; called explicitly at the end of `open(...)` and `openChapterBased(...)` so the restored locator reaches AI/TTS once before any scroll event. |
| 2 | Medium | `TXTReaderViewModel.swift:338` (`navigateToChapter`) | Chapter-mode navigation rewrites `currentOffsetUTF16`/`currentChapterLocalUTF16` directly without going through `updateScrollPosition`, so TTS after a TOC jump or chapter hop still uses the stale locator until the bridge reports another scroll event. | **Fixed**. Same `broadcastPosition` helper called inside `navigateToChapter`'s success branch. (See round-2 follow-up for failure-path correction.) |
| 3 | Low | `TXTReaderViewModelTests.swift:392`/`397` | The new tests register the observer with `queue: .main` and read `captured` synchronously — `NotificationCenter` with a non-nil queue can enqueue delivery, making these assertions timing-dependent. | **Fixed**. Helper switched to `queue: nil` for synchronous delivery on the posting thread. |

## Round 2 findings

| # | Severity | File:line | Issue | Resolution |
|---|---|---|---|---|
| 1 | Medium | `TXTReaderViewModel.swift:357`/`383` (post-round-1 `navigateToChapter` shape) | The new chapter-nav broadcast fires unconditionally even if `loadChapter` throws — the catch only sets `errorMessage` but execution continues into preload + broadcast. Observers can receive a phantom position-change for a chapter jump that never actually succeeded. | **Fixed**. Moved the `broadcastPosition(makeLocator())` call INTO the `do { ... }` block so the catch path skips the broadcast. |
| 2 | Low | `TXTReaderViewModelTests.swift:440` | The "open with restored position seeds AI/TTS via post once" test only asserted some locator was observed, not that exactly one notification fired. Future double-post regressions (e.g. one from restore + one from a stray scroll callback) wouldn't be caught. | **Fixed**. `observeLocator()` helper now also exposes a `count()` closure; the open-restore test pins `observer.count() == 1`. |
| 3 | Low | `TXTReaderViewModelTests.swift:402` | Stale doc comment on the helper still said "observer queue is .main" after the round-1 switch to `queue: nil`. | **Fixed in round 2 helper docstring + round-3 inline comment fix below.** |

## Round 3 findings

| # | Severity | File:line | Issue | Resolution |
|---|---|---|---|---|
| 1 | Low | `TXTReaderViewModelTests.swift:411` | An inline comment inside `postsNotificationOnPositionUpdate()` still said "the observer queue is .main" after the round-1 helper switch to `queue: nil`. | **Fixed**. Comment now matches: "the observer is registered with `queue: nil` (synchronous delivery on the posting thread)". |

Round-3 verification (post-fix): zero findings. Codex confirmed:
- Restore-on-open seeds AI/TTS immediately.
- Suppress-window still blocks storm-zero scroll broadcasts.
- Chapter navigation only broadcasts on successful loads.
- Test suite pins exact single-broadcast behavior for `open()`.

Final verdict: `ship-as-is`.

> "No findings. The last stale-comment issue is resolved, and the implementation/test shape now matches the intended behavior: restore-on-open seeds AI/TTS immediately; suppress-window still blocks storm-zero scroll broadcasts; chapter navigation only broadcasts on successful loads; the test suite now pins exact single-broadcast behavior for `open()`. Verdict: ship-as-is." — Codex round 3 follow-up

## Test gate

`xcodebuild test -only-testing:vreaderTests/TXTReaderViewModelPositionBroadcastTests` — **5/5 green** (all four scroll-broadcast tests + the open-restore-seed test).

Full unit suite at the time of audit: 756 tests across 78 suites, all Swift Testing assertions pass; full-suite tail still shows the pre-existing parallel-load flakiness documented in bug #167 (AutoPageTurner, TTSService Speed Control, ReaderSettingsStore.autoPageTurnInterval) that pass in isolation on both `main` and this branch — not related to this fix's code paths.

## Cross-format scope

The bug body says "TXT confirmed; EPUB likely affected too." This fix is
deliberately **TXT-only**:

- **EPUB**: `Locator` for EPUB doesn't carry `charOffsetUTF16` (EPUB uses
  `href + progression`), so `startTTS`'s `offset = ai.currentLocator?.charOffsetUTF16 ?? 0`
  would still resolve to 0 even if the EPUB locator IS being broadcast.
  Fixing EPUB-from-current-position requires computing a global UTF-16
  offset from the EPUB (`href`, `progression`) into the concatenated
  spine-item text that TTS receives via `loadedTextContent`. That's a
  larger refactor with its own correctness concerns (HTML stripping
  alignment, CFI-vs-progression resolution). Treated as separate scope —
  if reproduced as a distinct symptom, file as a follow-up bug.
- **AZW3/MOBI (Foliate)**: same shape as EPUB — uses CFI + progression, no
  `charOffsetUTF16`. Out of scope for the same reason.
- **PDF**: uses `page` for position — TTS likely concatenates text from all
  pages and starts from offset 0; same EPUB-shape issue. Out of scope.
- **MD**: already posts via `.onChange(of: viewModel.totalProgression)` in
  `MDReaderContainerView`, AND its locator carries `charOffsetUTF16` (same
  text-based shape as TXT). Should already work; no change needed.

## Plan compliance

Fix scope per the issue body matches:
- [x] Native TXT TTS now starts from the user's current scroll position, not offset 0.
- [x] Restore-on-open path seeds AI/TTS with the restored position once.
- [x] Chapter navigation broadcasts the new chapter's locator on successful loads.
- [x] Failed chapter loads don't emit phantom position-change events.
- [x] Suppress window correctness preserved — TextKit relayout storm-zero updates do NOT leak out.
- [x] Test coverage: 5 tests covering happy path, two clamping edges, restore-seed exact-count, and suppress-window behavior.

## Files OUT of scope

- `EPUBReaderContainerView.swift`, `FoliateViewBridge.swift`, `PDFReaderContainerView.swift` — locators don't carry `charOffsetUTF16`; fix needs different shape.
- `ReaderContainerView+Sheets.swift:startTTS()` — call site looks correct; the bug was upstream (TXT not broadcasting locator).
- `MDReaderContainerView.swift` — already posts `.readerPositionDidChange` via `.onChange(of: viewModel.totalProgression)`.
