---
branch: feat/feature-121-wi-3-tts-viewmodel
threadId: 019f0405-f121wi3
rounds: 2
final_verdict: ship-as-is
date: 2026-06-27
---

# Feature #121 WI-3 — Codex audit (TtsViewModel transport state machine)

Files: `tts/TtsViewModel.kt`, `tts/TtsUiState.kt`, `tts/TtsViewModelTest.kt` (13, Robolectric + fake engine).

## Round 1 — 3 High, 3 Medium, 2 Low (all fixed)

| severity | issue | resolution |
|---|---|---|
| High | `start()` re-entrant / not token-guarded across `awaitInit()`; empty start didn't stop/bump | FIXED — a `startToken` + post-suspend bail checks; entry bumps generation + `engine.stop()`; empty start bumps + stops |
| High | `engine.speak()` false ignored → could hang in `speaking` forever | FIXED — `speakOne()` checks the Boolean; on false → `failTerminal(speakFailed)` |
| High | `Failed` only set error (later same-gen callbacks could revive) | FIXED — `failTerminal`: `generation++` + `engine.stop()` + error |
| Medium | next/prev/selectVoice stopped BEFORE the generation bump (stale-callback window) | FIXED — centralized `restartFromCurrent()` bumps generation BEFORE `engine.stop()`; seek/selectVoice/play route through it |
| Medium | `Done` refill tied to `p.index==current` → a dropped `Started` could stall the queue | FIXED — refill on ANY same-generation `Done` (from `enqueuedThrough`); idle when the last index's Done arrives |
| Medium | `setVoice` failures ignored | FIXED — `selectVoice` keeps prior state on reject; start auto-pick sets the label only if accepted |
| Low | `queueWindow` unvalidated | FIXED — coerced `>= 1` |
| Low | `rateLabel` default-locale formatting | FIXED — `Locale.ROOT` |

## Round 2 — 1 High (fixed)

| severity | issue | resolution |
|---|---|---|
| High | `startToken` was bumped INSIDE the launched coroutine → a `stop()` racing before the coroutine ran wasn't visible, so a stale start could enqueue after stop | FIXED — `start()` captures `val token = ++startToken` SYNCHRONOUSLY before `viewModelScope.launch` (and stops/bumps generation synchronously); the coroutine bails immediately if `token != startToken` and re-checks after each suspend. `start()` returns the `Job`. |

Round 2 confirmed no problem with the double generation bump, the `speakOne`/`failTerminal` mid-loop
path, or the Done-refill ordering (bounded + ordered under the engine's one-terminal-callback-per-
utterance contract). Regression tests added: `speakFailure_entersError`, `failedEvent_isTerminal_noRevive`.

## Summary

3 High + 3 Medium + 2 Low (R1) + 1 High (R2), all fixed. 13 Robolectric tests green. **Verdict: ship-as-is.**
