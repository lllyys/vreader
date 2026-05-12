---
branch: feat/feature-48-wi-3-creation-translation
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-12
---

# Codex Audit — Feature #48 WI-3

**Codex MCP unavailable (stream disconnected)**. Manual fallback audit per `.claude/rules/47-feature-workflow.md`.

## Manual Audit Evidence

**Files read:**
- `vreader/Services/Locator/LocatorFactory.swift` (lines 150–190)
- `vreader/Views/Reader/ReaderNotificationHandlers.swift` (lines 35–68)
- `vreader/Views/Reader/TXTReaderContainerView.swift` (lines 403–440, 619–646)

**Symbols verified:**
- `LocatorFactory.txtChapterRange(fingerprint:chapterLocalStart:chapterLocalEnd:chapterText:chapterGlobalStart:)` — added correctly
- `TXTReaderContainerView.makeLocatorForTXT(fingerprint:localStart:localEnd:chapterText:chapterGlobalStart:isChapterMode:)` — added as static seam
- `ReaderNotificationDeps.locatorFactory: @MainActor (...)` — changed from `@Sendable` correctly
- `makeNotificationDeps()` closure — captures `viewModel` directly, dispatches through `makeLocatorForTXT`

**Edge cases checked:**
- `txtChapterRange`: negative `chapterLocalStart` → nil ✓
- `txtChapterRange`: inverted range (`end < start`) → nil ✓
- `txtChapterRange`: `end > chapterText.utf16.count` → nil ✓
- `txtChapterRange`: `chapterGlobalStart = 0` → identity (local == global) ✓
- `makeLocatorForTXT`: `isChapterMode=true, chapterText=nil` → nil (fixed post-audit) ✓
- `makeLocatorForTXT`: `isChapterMode=false` → delegates to `txtRange` (passthrough) ✓
- `@MainActor` call sites: `ReaderNotificationModifier` handlers are `@MainActor` via SwiftUI ✓
- `viewModel` capture in closure: `viewModel` is `@MainActor @Observable`, safe to capture in `@MainActor` closure ✓

**Risks accepted:**
- None.

## Round 1 Findings

| # | Severity | Finding | Location | Fix |
|---|----------|---------|----------|-----|
| 1 | Low | `makeLocatorForTXT` with `isChapterMode=true, chapterText=nil` fell through to `txtRange`, treating chapter-local offsets as global | `TXTReaderContainerView.swift:631` | Changed to `guard let text = chapterText else { return nil }` — returns nil instead of wrong locator |

## Resolution

- Finding 1 (Low): Fixed. `isChapterMode=true` with nil `chapterText` now returns nil rather than a malformed global-offset locator.

## Summary Verdict

Round 1: 1 Low finding, fixed. Round 2 (verbal review): no new issues from the fix — `guard nil return` is idiomatic and safe.

All 8 WI-3 tests pass (5 `LocatorFactoryTXTChapterTests` + 3 `TXTChapterHighlightCreationTests`).

**Verdict: ship-as-is**
