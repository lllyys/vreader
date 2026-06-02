---
branch: feat/feature-82-wi-2-bug308-availability
threadId: 019e886c-6c61-7913-a71a-403eb9ccdd20
rounds: 1
final_verdict: ship-as-is
date: 2026-06-02
---

# Gate-4 implementation audit — Feature #82 WI-2 (Bug #308 entry + AIReaderAvailability alignment)

Codex gpt-5.5 / high, read-only (via `scripts/run-codex.sh`). Audited the
`AIReaderAvailability` alignment (the Gate-2 Critical) + the standalone
`ReaderAIReadinessSheet` (Bug #308 AI-button entry) + the `ReaderContainerView.onAI`
routing.

## Verdict

Round 1: **follow-up-recommended** — 0 Critical/High, 2 Medium. Both FIXED → post-fix
**ship-as-is**. Auditor confirmed the core no-legacy regression: active provider +
per-profile key now makes `isAvailable` pass (fixing the #308 loop); the active-id
UserDefaults read is synchronous + fresh per access.

## Findings + resolutions

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `AIReaderAvailability.swift` | Medium | Legacy-key fallback ran BEFORE the active-provider check — a stale legacy key could mask a key-less active profile, making `isAvailable` true while the live request throws `apiKeyMissing` (divergent from the live gate) | Reordered: **active provider first** (its per-profile key is authoritative when an active profile exists); legacy fallback only when NO active profile. New inverse test `unavailable_legacyKeyButActiveProviderHasNoKey`. |
| `ReaderContainerView.swift` | Medium | `onReady` set `showAIReadiness=false` + `showAIPanel=true` in one update (sibling-sheet handoff drops the panel) | `onReady` sets a `pendingOpenAIPanelAfterReadiness` flag + dismisses readiness; the panel opens from the readiness sheet's `.sheet(onDismiss:)` (the #81 pattern). |

## Tests

- `AIReaderAvailabilityPerProfileTests` (7): per-profile key (no legacy) → available
  (the #308 regression); flag-off / no-consent / keyless-active / no-provider-no-legacy
  → unavailable; legacy fallback (no profiles) → available; **legacy key + keyless
  active profile → unavailable** (the Gate-4 fix). Existing `AIReaderIntegrationTests`
  + `ReaderAIProvidersFlowTests` regression green.
