---
branch: feat/56-wi-5-aiservice-resolved-config
threadId: 019e416f-07b2-7682-aace-68b0dc294927
rounds: 2
final_verdict: ship-as-is
date: 2026-05-20
---

# Codex Audit — feat/56-wi-5-aiservice-resolved-config

**Feature**: #56 — bilingual reading mode (WI-5, foundational).
**Scope**: the `AIService` resolved-provider seam — `ResolvedAIProviderConfig`
(immutable config snapshot), `resolveActiveProviderConfig()`,
`resolveProviderConfig(profileID:modelOverride:)`, `sendRequest(_:using:)`.
**Auditor**: Codex (`mcp__plugin_codex-toolkit_codex__codex`), read-only sandbox.
**Thread**: `019e416f-07b2-7682-aace-68b0dc294927`. Gate 4 — implementation audit.

## Round 1 — 3 findings (0 Critical, 0 High, 1 Medium, 2 Low)

Codex confirmed: the cache bypass is implemented correctly (`sendRequest(_:using:)`
never touches `AIResponseCache`); credential pinning is correct (`config(from:)`
reads the key once, `sendRequest(_:using:)` never re-reads); `ResolvedAIProviderConfig`
is safely `Sendable`; no overload ambiguity with the existing `sendRequest(_:)`;
no apiKey logging/persistence leak.

1. **Medium — the resolved-config path skipped `providerFactory`.** The plan
   says `resolveActiveProviderConfig()` honors `provider`/`providerFactory`
   test-injection precedence, but the first cut's `static provider(for:)` only
   honored `provider`, always falling through to production dispatch — a test
   using `providerFactory` (not `provider`) would silently hit production
   provider construction.
   **Fix**: replaced `static provider(for:)` with an instance method
   `providerInstance(for:)` honoring the SAME precedence as `resolveProvider()`
   — `provider` → `providerFactory` → production switch. For the factory seam,
   the config is reflected back into a `ProviderProfile` via a private
   `profile(reflecting:)` helper.

2. **Low — "no active profile" / "unknown profileID" tests asserted only
   `any Error`** — the typed-`AIError` edge-case contract was unproven.
   **Fix**: the tests now assert the exact
   `AIError.providerError("Configure a provider in Settings.")` /
   `AIError.providerError("The selected AI provider no longer exists.")`.

3. **Low — pinning + factory coverage gap.** No test directly proved the
   "key read once, pinned across send" behavior or the `providerFactory` path.
   **Fix**: added `sendRequestUsing_honorsProviderFactoryInjection` (a
   capturing factory records the (profile, apiKey) the resolved-config path
   builds with) and `sendRequestUsing_keepsResolvedCredentialAfterKeychainRotation`
   (resolve config → rotate the Keychain key → send → assert the send path
   used the ORIGINAL pinned key). A thread-safe `CapturedFactoryArgs` backs
   the `@Sendable` factory closure.

## Round 2 — 0 findings

Codex confirmed the round-1 Medium is genuinely resolved (the resolved-config
path now honors `provider` AND `providerFactory`), the `profile(reflecting:)`
reflection is sound (private, not persisted, not logged, no new credential
leak/re-read window), the Low findings are resolved, and no new
Critical/High/Medium was introduced — cache bypass intact, existing API
unchanged.

## Disposition

Zero Critical/High/Medium after round 2. Final verdict: **ship-as-is**.
