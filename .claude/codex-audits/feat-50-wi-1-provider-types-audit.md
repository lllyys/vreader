---
branch: feat/50-wi-1-provider-types
threadId: 019e127d-a8c3-7450-98e1-a610487b9460
rounds: 2
final_verdict: ship-as-is
date: 2026-05-10
---

# Codex Gate-4 audit — feature #50 WI-1 (foundational types)

Files audited:

Production:
- `vreader/Services/AI/ProviderKind.swift`
- `vreader/Services/AI/ProviderProfile.swift`
- `vreader/Services/AI/KeychainService+ProviderProfile.swift`

Tests:
- `vreaderTests/Services/AI/ProviderKindTests.swift`
- `vreaderTests/Services/AI/ProviderProfileTests.swift`
- `vreaderTests/Services/AI/KeychainProviderProfileExtensionTests.swift`

## Round 1 findings

| # | Severity | File:line | Issue | Resolution |
|---|---|---|---|---|
| 1 | Medium | `vreaderTests/Services/AI/ProviderProfileTests.swift:62` | `structuralEqualityCoversAllFields` did not vary `id` — a future custom `==` that ignored identity would have passed. | **Fixed**. Added a case where only `id` differs (all other fields match) and asserted inequality. Comment explains why id-participation matters for downstream active-profile logic. |
| 2 | Low | `vreaderTests/Services/AI/ProviderKindTests.swift:40` | Default-model tests only asserted non-empty strings; silent regressions from the planned `gpt-4o-mini` / `claude-sonnet-4-6` defaults would have passed. | **Fixed**. Tests renamed `defaultModelOpenAIIsLocked` / `defaultModelAnthropicIsLocked`. Assert exact strings; comment explains why the values are locked (UI prefill in WI-6). |

Production code audited clean in round 1: `URL(string:)!` literals are safe (static, well-formed); `KeychainService.delete` semantics preserved including non-`errSecItemNotFound` rethrow; account format exposes only the UUID; per-test keychain service identifiers are sufficient to prevent cross-run pollution in practice.

## Round 2 verification

Both round-1 fixes verified correct. No new issues introduced. Verdict: `ship-as-is`.

> "The two round-1 fixes are correct. `ProviderProfileTests` now proves `id` participates in structural equality by varying only that field… `ProviderKindTests` now lock the exact planned defaults… No new issues were introduced by these edits." — Codex round 2

## Test gate

`xcodebuild test -only-testing:vreaderTests/ProviderKindTests -only-testing:vreaderTests/ProviderProfileTests -only-testing:vreaderTests/KeychainProviderProfileExtensionTests` — 24/24 tests green (round-1 baseline). Re-run after audit fixes — `** TEST SUCCEEDED **`.

## Plan compliance

WI-1 deliverables per `dev-docs/plans/20260510-feature-50-multi-provider-ai.md`:

- [x] `ProviderKind` enum with `openAICompatible` + `anthropicNative` cases, Codable + Sendable + CaseIterable, `defaultBaseURL` / `defaultModel` / `displayName` accessors.
- [x] `ProviderProfile` struct with `id: UUID`, `name`, `kind`, `baseURL`, `model`, `temperature`, `maxTokens`, conforming to Codable + Sendable + Equatable + Identifiable. apiKey deliberately NOT a stored property.
- [x] `KeychainService+ProviderProfile.swift` extension with `static func providerAccount(for: UUID)` returning `com.vreader.ai.apiKey.<uuid>`, plus `readAPIKey` / `saveAPIKey` / `deleteAPIKey` per-profile wrappers composing with the existing primitives.

Tier classification preserved: WI-1 is **Foundational** — no user-observable behavior, no persistence, no network, no UI. Unit tests + this audit are the verification (Gate 5a slice not required).

## Files OUT of WI-1

These come in later WIs and are NOT touched here:

- `ProviderProfileStore` (WI-2)
- `ProviderProfileMigrator` (WI-2)
- `AnthropicProvider` (WI-3 + WI-4)
- `AIService` modifications (WI-5)
- Settings UI rewrites (WI-6a + WI-6b)
- In-reader picker (WI-7)
- `AIConfigurationStore` deprecation (NOT in this feature; follow-up PR)
