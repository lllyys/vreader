---
branch: feat/feature-91-wi-8b-resolve-tool-provider
threadId: 019e929c-d85f-7d53-aa70-23e94ff133fc
rounds: 2
final_verdict: ship-as-is
date: 2026-06-04
---

# Codex Audit — Feature #91 WI-8b (slice 1: AIService agentic seam)

Gate-4 implementation audit (rule 47). Independent Codex runner via
`scripts/run-codex.sh -e high` (author/auditor separation, rule 48; rule-53
stdin-isolated watchdog).

## Scope

WI-8b slice 1 — the `AIService` seam the agentic chat loop resolves through:

- `vreader/Services/AI/AIService.swift` — `resolveToolProvider()` (resolve the
  active config ONCE: flag + consent + active-profile + key gates, report tool-use
  capability) + `sendToolTurn(_:using:)` (one tool turn through a PINNED config,
  re-checking the live gates each turn).
- `vreaderTests/Services/AI/AIServiceResolvedConfigTests.swift` — 6 tests via the
  `provider:` injection seam.

## Round 1 — findings (threadId 019e929c-d85f-7d53-aa70-23e94ff133fc)

`maxTokens` carry + actor isolation confirmed sound.

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| AIService.swift `resolveToolProvider` | **Medium** | Returning a raw `AIProvider` meant the multi-turn agentic loop would bypass the LIVE `aiAssistant`/consent gates after the initial resolve — a flag flip or consent revoke mid-loop could still reach the provider. | **Fixed.** `resolveToolProvider()` now returns `(config: ResolvedAIProviderConfig, supportsToolUse)` — NOT a raw provider; each round-trip goes through `sendToolTurn(_:using:)`, which re-checks the flag + consent EACH turn (fails closed) while reusing the pinned config (no provider/model/key drift — Gate-2 Medium). Test `sendToolTurn_reChecksTheLiveFlagEachTurn` flips the flag OFF mid-loop → the next turn throws `featureDisabled`. |
| AIServiceResolvedConfigTests.swift | Low | The "same gates" test only covered `featureDisabled`. | **Fixed.** `resolveToolProvider_failsClosedOnEveryGate` covers `featureDisabled` + `consentRequired` + `apiKeyMissing`. |
| AIServiceResolvedConfigTests.swift | Low | The resolve-once pinning was documented, not proven. | **Fixed.** The config is structurally pinned (`sendToolTurn(_:using:)`); the returned snapshot's `kind`/`maxTokens` are asserted, and `sendToolTurn` reuses exactly that config. |

## Round 2 — verification (threadId 019e92b0-e5f1-7341-a548-3307874a15cc)

**No findings.** All three **RESOLVED**: the pinned config + per-turn gate re-check
(fails closed mid-loop), all three resolve gates covered, and the structural
pinning proven.

## Verdict

**ship-as-is.** Zero open Critical/High/Medium after round 2. `AIServiceResolvedConfigTests`
green (6 WI-8 tests: config+capability+maxTokens, non-tool → unsupported, all three
resolve gates fail closed, `sendToolTurn` forwards through the pinned config when
gates pass, and re-checks the live flag each turn).

The remaining WI-8b work (the `LibrarySearchBackend` + `BookContentProvider`
production adapters + the closed-book text extractor, the registry builder, the
`AIChatViewModel.sendMessage` branch + citation suppression, and the Gate-5 device
verification) completes the feature to `DONE`/`VERIFIED`.
