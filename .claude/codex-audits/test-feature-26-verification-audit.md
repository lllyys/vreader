---
branch: test/feature-26-verification
threadId: 019e3f37-5e03-7413-9d9e-2af2841855c6
rounds: 1
final_verdict: follow-up-recommended
date: 2026-05-19
---

# Codex audit — feature #26 CU-free XCUITest verification suite

## Scope

Gate-4 implementation audit of the two Swift files changed by the
feature #26 (Text-to-Speech read aloud) Gate-5 verification PR:

- `vreader/Services/TTS/XCUITestMockSpeechSynthesizer.swift` — DEBUG-only
  (`#if DEBUG`) test-harness synthesizer used solely by XCUITest via
  `--tts-test-mode`. This PR rewrites its synthetic-callback timeline
  into a self-rescheduling tick that genuinely suspends while paused.
- `vreaderUITests/Verification/Feature26TextToSpeechVerificationTests.swift`
  — new pure-XCUITest verification suite (3 tests, TXT/MD/EPUB).

No feature #26 production code (`TTSService`, `TTSControlBar`,
`startTTS()`) was modified.

Mini audit (5 dimensions: logic, duplication, dead code, refactoring
debt, shortcuts), Codex `gpt-5.2-codex` / effort `medium`, read-only.

## Findings

| # | File:Line | Dimension | Severity | Issue | Disposition |
|---|-----------|-----------|----------|-------|-------------|
| 1 | XCUITestMockSpeechSynthesizer.swift `speak()` | Logic & Correctness | Medium | A superseding `speak()` fired `didCancel` for the *new* utterance, not the outgoing one — diverges from real `AVSpeechSynthesizer` delegate semantics. | **Fixed** — added a `currentUtterance` field; `speak()` now fires `didCancel` with the outgoing utterance. |
| 2 | XCUITestMockSpeechSynthesizer.swift `stopSpeaking()` | Logic & Correctness | Medium | `stopSpeaking()` always returned `true` and always fired `didCancel`, even from the idle state. | **Fixed** — guarded with `isSpeaking || isPaused`; returns `false` and fires nothing when idle, matching `AVSpeechSynthesizer.stopSpeaking(at:)`. |
| 3 | XCUITestMockSpeechSynthesizer.swift `stopSpeaking()` | Logic & Correctness | Low | `stopSpeaking()` fired `didCancel` with a manufactured empty placeholder utterance. | **Fixed** — now fires `didCancel` with the actual in-flight `currentUtterance`. |
| 4 | Feature26TextToSpeechVerificationTests.swift `openSeededBook` (card path) | Flakiness | Medium | Taps the book card on bare `exists` when `waitForHittable` failed. | **Accepted** — this is the verbatim `waitForHittable(timeout:) || element.exists` retry-with-fallback pattern from the feature-#54 / #63 pilots (`Feature54ReadingModeRemovalVerificationTests.openSeededBook`). It is deliberate: `isHittable` flickers during `LazyVGrid` layout, and the enclosing 3× retry loop is the real safety net. All 3 tests passed cleanly across multiple runs — the flake did not materialize. Keeping the suite consistent with the established pilot pattern. |
| 5 | Feature26TextToSpeechVerificationTests.swift `openSeededBook` (row path) | Flakiness | Medium | Same `|| .exists` fallback for the list-mode `bookRow_` path. | **Accepted** — same rationale as #4. |
| 6 | Feature26TextToSpeechVerificationTests.swift `runTTSLifecycle` (C4) | Flakiness | Low | The Stop-button-gone assertion checked `stopButton.exists` immediately, with no settle window. | **Fixed** — changed to `stopButton(in:).waitForDisappearance(timeout: 8)`. |

Codex's closing note: the self-rescheduling tick logic is sound —
generation invalidation prevents stale callbacks, pause/resume re-entry
does not double-schedule, `stopSpeaking()` mid-sequence invalidates
future ticks correctly. The XCUITest suite has no dead code, no fixed
sleeps, and reasonable helper extraction.

## Verdict

`follow-up-recommended` — zero Critical/High findings. Four of the six
findings (the three mock-fidelity issues + the Stop-button settle
window) were fixed in this PR. The two remaining Medium findings (#4,
#5) are an explicitly-accepted, intentional pattern carried over verbatim
from the feature-#54 / #63 verification pilots; the suite passed all
3 tests across multiple runs, so the flagged flake risk did not
materialize. No blocking issues — safe to merge.
