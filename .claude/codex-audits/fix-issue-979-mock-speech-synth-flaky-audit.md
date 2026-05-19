---
branch: fix/issue-979-mock-speech-synth-flaky
threadId: 019e41e4-177b-7bb1-b00b-837eb6f30148
rounds: 3
final_verdict: ship-as-is
date: 2026-05-20
---

# Codex Audit — Bug #236 (GH #979): flaky XCUITestMockSpeechSynthesizerTests

## Scope

GH issue #979 / `docs/bugs.md` row #236 — `XCUITestMockSpeechSynthesizerTests`
and `BackgroundIndexingCoordinatorTests` used fixed `Task.sleep(<duration>)`
then asserted the result of timeline-/background-driven async work. Under CPU
contention the wall-clock dispatch (`DispatchQueue.main.async`, `asyncAfter`,
detached `Task`s) lags past the sleep, so the assertion runs before the work
completes → flaky failures.

Fix: a shared `pollUntil` helper that waits on the *actual* completion signal
with a generous timeout, and conversion of every load-sensitive
fixed-sleep-then-assert site to use it.

Files changed:
- `vreaderTests/Helpers/PollUntil.swift` (new — shared deterministic-wait helper)
- `vreaderTests/Services/TTS/XCUITestMockSpeechSynthesizerTests.swift`
- `vreaderTests/Services/Search/BackgroundIndexingCoordinatorTests.swift`
- `vreader.xcodeproj/project.pbxproj` (xcodegen re-enumeration for the new file)
- `docs/bugs.md` (row #236 status)

## Round 1 — initial audit

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 1 | `vreaderTests/Helpers/PollUntil.swift` | High | New helper file was untracked and absent from `vreader.xcodeproj` — a clean checkout's `vreaderTests` target would fail to compile (`BackgroundIndexingCoordinatorTests` references `pollUntil`). | Fixed — `git add` the file and ran `xcodegen generate`; the `vreaderTests` folder-glob source picked it up (verified the references land in `project.pbxproj`). |
| 2 | `XCUITestMockSpeechSynthesizerTests.swift` `speakFiresWillSpeakRangeMultipleTimes` | Medium | Still used a fixed `Task.sleep(1.5s)` then asserted `willSpeakRangeCount >= 2` — the exact flaky pattern the bug is about. | Fixed — converted to `await pollUntil { delegate.willSpeakRangeCount >= 2 }`. |
| 3 | `XCUITestMockSpeechSynthesizerTests.swift` `speakFiresDidStartPromptly` | Low | Still used a fixed `Task.sleep(100ms)` then asserted `didStartCount == 1`. | Fixed — converted to `await pollUntil { delegate.didStartCount == 1 }`. |

## Round 2 — verify

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 1 | `XCUITestMockSpeechSynthesizerTests.swift` `secondSpeakCancelsFirst` | Medium | Still contained two load-sensitive fixed sleeps: a `Task.sleep(300ms)` gating the first `didStart` before the second `speak()`, and a `Task.sleep(200ms)` before `#expect(didStartCount == 2)`. The second utterance's `didStart` is delivered via `DispatchQueue.main.async`, so the 200ms can elapse first under load. | Fixed — `Task.sleep(300ms)` → `await pollUntil { delegate.didStartCount == 1 }` (preserves the load-bearing gate that the first `didStart` lands before the mock's generation counter is bumped by the second `speak()`); `Task.sleep(200ms)` → `await pollUntil { delegate.didStartCount == 2 }`. The synchronous-state asserts (`didCancelCount >= 1`, `mock.isSpeaking == true`) now run immediately after the second `speak()` with no sleep, since both flip synchronously inside `speak()`. |

## Round 3 — verify

Clean. Codex confirmed `secondSpeakCancelsFirst` is correct and complete, with
no remaining load-sensitive fixed-sleep-then-assert patterns across the diff —
all four converted sites in the TTS file, the eight rewritten cases in
`BackgroundIndexingCoordinatorTests`, and the `PollUntil.swift` helper itself.
`stopSpeakingFiresDidCancelAndHaltsCallbacks` deliberately keeps its sleeps
because it asserts the *non-occurrence* of callbacks within a bounded window —
correct by design, not a finding. `MockSearchService.indexBook`'s mock delay is
test setup, not a flaky wait-before-assert.

## Verdict

**ship-as-is** — 3 rounds, all findings (1 High, 2 Medium, 1 Low) fixed; round 3
clean.
