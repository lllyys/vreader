---
branch: fix/issue-910-ttsservice-rate-recursion
threadId: 019e3ee8-ad79-7150-b1c9-0c675dc1f146
rounds: 1
final_verdict: ship-as-is
date: 2026-05-19
---

# Codex Audit — Issue #910 / Bug #226: `TTSService.rate` `didSet` infinite recursion

## Scope

Diff `git diff origin/main` on branch `fix/issue-910-ttsservice-rate-recursion`
(rebased on `origin/main` @ `4c38293`). Substantive files:

- `vreader/Services/TTS/TTSService.swift` — `rate` converted from a stored
  property with a clamping `didSet` (which self-assigned `rate` and recursed
  unboundedly under the `@Observable` macro) to a computed `get`/`set` over a
  new `private var _rate: Float = 0.5`, clamping in `set`.
- `vreaderTests/Services/TTSServiceTests.swift` — added
  `speedControl_inRangeAssignmentDoesNotRecurse`, a same-value post-init
  re-assignment regression test mirroring the Bug #222 regression test.
- `docs/bugs.md` — tracker bookkeeping only (renumber colliding row 225 → 226,
  status flip); excluded from the code audit.

## Round 1

**Verdict: No findings.**

Codex notes (paraphrased):

| Area | Finding |
|---|---|
| `TTSService.swift:43` recursion break | Correct. Old failure mode = `didSet` writing `rate` again; new computed `rate` writes only `_rate`, so there is no self-reentry path. `_rate`'s `0.5` initializer preserves the old default exactly. |
| `TTSService.swift:68` (`init`) + `:156` (`startSpeaking`) | Compatible. `init` does not touch `rate`; `startSpeaking` still reads the public property and applies the clamped value to `AVSpeechUtterance`. |
| `@Observable` observation | Sound. A view observing `rate` reads `_rate` through the getter, so dependency tracking attaches to `_rate`; writes to `_rate` in the setter invalidate those observers. |
| Concurrency | No regression. Class is already `@MainActor`; the new backing store introduces no isolation concern. |
| Numeric edges (`TTSService.swift:45`) | Acceptable. `0.0`/`1.0` stable; `+infinity` clamps to `1.0`; `-infinity` clamps to `0.0`; `NaN` collapses to `0.0` with Swift's `min`/`max` behavior rather than propagating. |
| Test quality (`TTSServiceTests.swift:147`) | Meaningful regression test, not wiring-only. Exercises the exact post-init same-value reassignment that previously crashed. Pre-existing speed tests (`:96-135`) cover default, in-range mutation, both clamp directions, and propagation into the utterance — together adequate. |

Codex did not run `xcodebuild` as part of the audit.

## Resolution

Zero findings of any severity. No fixes required.

## Summary verdict

**ship-as-is** — 1 round, clean. The fix mirrors the proven Bug #222 pattern
(`ReaderSettingsStore.autoPageTurnInterval`) and the sibling
`ReaderSettingsStore.backgroundOpacity`; correctness, `@Observable`
observation, concurrency, and numeric-edge behavior all verified.
