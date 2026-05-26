---
branch: feat/feature-72-wi-0-speechsynthesizing-delegate
threadId: 019e6396-7164-7931-bdd0-512c84f310e0
rounds: 1
final_verdict: ship-as-is
date: 2026-05-26
---

# Codex audit — Feature #72 WI-0 (SpeechSynthesizing.delegateTarget protocol hoist)

Gate-4 audit (Codex MCP) of WI-0: hoist `delegateTarget` onto the
`SpeechSynthesizing` protocol + wire it generically in `TTSService` (no
type-casing), so the forthcoming `HTTPSpeechSynthesizer` adapter receives
delegate callbacks.

Files: `SpeechSynthesizing.swift`, `TTSService.swift`, `TTSServiceTests.swift`.

## Round 1 — clean (no findings)

Codex confirmed:
- Behavior-identical for existing concrete paths — both `SystemSpeechSynthesizer`
  (forwards into `AVSpeechSynthesizer.delegate`) and `XCUITestMockSpeechSynthesizer`
  already exposed the same weak delegate slot; the generic `synthesizer.delegateTarget = self`
  sets it exactly as the prior type-cast did. No path intentionally left the
  delegate unset.
- Ownership non-cyclic: `TTSService` strongly owns the synthesizer; conformers
  weak-ref `delegateTarget`. No retain cycle.
- No new isolation/Sendable issue: assignment in `TTSService.init` on MainActor;
  protocol staying non-`@MainActor` is consistent with the existing abstraction.
- `#if DEBUG` removal benign: the new unconditional line references no DEBUG-only
  symbol; Release sets the delegate on `SystemSpeechSynthesizer` as before.
- Test quality good: `init_wiresDelegateGenerically_forAnySynthesizer` proves a
  plain mock now gets wired.

Residual (not a finding): the protocol can't express `weak`, so a future
conformer could implement `delegateTarget` as a strong ref — convention only.

## Verification

`TTSServiceStateTransitionTests` (10 tests incl. the new generic-wiring guard)
pass; the protocol change compiles across all conformers (UDID-pinned,
`-parallel-testing-enabled NO`).

## Verdict

**Ship-as-is.** No findings. Foundational refactor, behavior-preserving.
