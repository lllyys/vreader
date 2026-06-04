---
branch: feat/feature-91-wi-8b-service-tooluse-adapter
threadId: 019e935d-6dfd-7f00-be4d-ba23a6047b47
rounds: 1
final_verdict: ship-as-is
date: 2026-06-05
---

# Codex Audit — Feature #91 WI-8b (slice 5: AIServiceToolUseAdapter)

Gate-4 implementation audit (rule 47). Independent Codex runner via
`scripts/run-codex.sh -e high` (author/auditor separation, rule 48; rule-53
stdin-isolated watchdog).

## Scope

WI-8b slice 5 — the PRODUCTION `ToolUseSending` the agentic chat loop uses:

- `vreader/Services/AI/AIChatAgenticSupport.swift` — `AIServiceToolUseAdapter`
  wraps `(AIService, ResolvedAIProviderConfig)` and forwards each driver turn
  through `AIService.sendToolTurn(_:using:)` (live flag/consent re-check each turn,
  pinned config). The callerless `ProviderToolUseAdapter` (WI-8a) was removed.
- `vreaderTests/Services/AI/AIServiceResolvedConfigTests.swift` — 2 adapter tests.

## Audit (threadId 019e935d-6dfd-7f00-be4d-ba23a6047b47)

> The first run (threadId 019e9359) was watchdog-killed at 210s while exploring the
> full test suite, before producing a verdict; re-run concise.

**No finding on the adapter's correctness or Swift 6 story:** the forward to
`sendToolTurn` is correct, and the `Sendable` story is sound (`AIService` is an
actor, `ResolvedAIProviderConfig` is `Sendable`). **No finding on the test seam:**
the `provider:` injection is acceptable for these two tests — the adapter's job is
only "delegate to `sendToolTurn`"; config→provider construction is `AIService`'s
responsibility and is covered by the existing `sendRequestUsing` factory-seam tests.

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| AIChatAgenticSupport.swift `ProviderToolUseAdapter` | Low | Now callerless dead code, and being non-gate-rechecking it's a production footgun (a future caller could pick the wrong bridge). | **Fixed.** Removed (it had no callers and no tests; build green confirms no dangling references). A non-gating bridge can be reintroduced at a concrete caller with local docs/tests if ever needed. |

## Verdict

**ship-as-is.** Zero open Critical/High/Medium. The Low (dead-code removal) is a
build-verified deletion of unused code. `AIServiceResolvedConfigTests` green
(the adapter forwards through `sendToolTurn` and fails closed on a mid-loop flag
revoke; `AIChatAgenticSupportTests` green after the removal).

The only remaining WI-8b work — the `AIChatViewModel.sendMessage` branch
(driver via `AIServiceToolUseAdapter` over `sendToolTurn` vs stream) + citation
suppression + the construction-site registry wiring, `docs/architecture.md`, and
Gate-5 device verification — completes Feature #91 to `DONE`/`VERIFIED`.
