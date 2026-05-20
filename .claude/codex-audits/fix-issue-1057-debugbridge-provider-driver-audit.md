---
branch: fix/issue-1057-debugbridge-provider-driver
threadId: 019e452c-fd12-78a0-beda-eeae95720b83
rounds: 2
final_verdict: ship-as-is
date: 2026-05-20
---

# Codex Gate-4 Audit — Bug #243 (GH #1057): DebugBridge `provider` driver

## Scope

DebugBridge `vreader-debug://provider?action=add|remove|clear` URL family
that lets verification harnesses configure AI provider profiles in
`ProviderProfileStore` + per-profile API keys in `KeychainService` without
driving Settings → AI through computer-use. Unlocks autonomous AI-feature
verification (Feature #56 b/d criteria, Feature #65/#69, Bug #93)
regardless of CU availability.

DEBUG-only across the entire surface; `verify-release-no-debugbridge.sh`
continues to pass (every touched file is `#if DEBUG`-wrapped).

## Round 1 — findings (4)

### Medium #1 — `DebugCommand.swift:345-352` — `endpoint` validation weaker than the comment claims

**Issue**: Original parser accepted any URL with `scheme == "http" || scheme == "https"`. This admits opaque forms like `https:foo` (parseable, scheme set, `host == nil`) and non-localhost `http://example.com` (which the runtime providers would reject anyway). The bridge could persist provider profiles the app cannot actually use, defeating pre-flight validation.

**Fix**: Tightened to mirror `AISettingsViewModel.validateBaseURL`:
- Require parseable URL with a non-empty `host` (rejects `https:foo`).
- Require `https` scheme except for `host == "localhost" || host == "127.0.0.1"` (rejects `http://example.com`, accepts `http://localhost:11434/v1`).

**Test coverage added**: `test_parse_providerAddOpaqueEndpoint_throwsInvalidParam`, `test_parse_providerAddHTTPNonLocalhostEndpoint_throwsInvalidParam`, `test_parse_providerAddHTTPLocalhostEndpoint_isAccepted`, `test_parse_providerAddHTTP127LoopbackEndpoint_isAccepted`.

**Status**: fixed in round 1, verified clean in round 2.

### Medium #2 — `RealDebugBridgeContext+Provider.swift:72-86,106-117` — `add` duplicates by name, breaking `remove(name:)`

**Issue**: Original `addProvider` always minted a fresh `UUID()`. Re-running `provider?action=add&name=OpenRouter...` created multiple profiles with the same display name. `removeProvider(name:)` keys on name and takes `.first(where:)` — non-deterministic which one gets removed.

**Fix**: Look up an existing profile by name first; when found, reuse its UUID + keychain account (replace-in-place). Otherwise mint a new UUID. Re-running an `add` URL is now idempotent at the URL boundary.

**Test coverage added**: `test_provider_addTwiceWithSameName_reusesUUID_andUpdatesFields` — verifies (a) no duplicate row, (b) UUID stable across re-add, (c) fields (model) updated, (d) keychain entry overwritten under the same per-profile account.

**Docs updated**: URL grammar row + parameter validation in `docs/subsystems/debug-bridge.md` now describe the replace-by-name behavior.

**Status**: fixed in round 1, verified clean in round 2.

### Low #3 — `RealDebugBridgeContext+Provider.swift:125-143` — `clear` is snapshot-based, not actor-atomic

**Issue**: The bridge serializes its own commands but an out-of-band writer using `ProviderProfileStore.shared` directly could land a new profile between `loadAll()` and the removal loop. That new profile would survive `clear`.

**Resolution**: Accepted. The `DebugBridge` itself serializes; verification flows do not exercise the AI subsystem in parallel with `provider?action=clear`. If a future flow needs strict atomicity, the fix belongs on `ProviderProfileStore` (an actor-level `removeAll()`), not in the bridge — this is a DEBUG-only verification harness, not production code.

**Documentation**: Added a "Concurrency caveat (Round-1 Codex audit Low, accepted)" comment on `clearProviders` describing the gap + the right place to fix it if needed.

**Status**: accepted with rationale, documented in code; verified clean in round 2.

### Low #4 — `RealDebugBridgeContext+Provider.swift:82-85` — apiKey not trimmed before save

**Issue**: Production `AISettingsViewModel.addProfile(_:apiKey:)` trims the API key with `.whitespacesAndNewlines` before save. The bridge handler did not. A host-side quoting / encoding mistake (e.g. `apiKey=$(cat .secrets/key.txt)` with a trailing newline) would leave whitespace in Keychain and produce avoidable auth failures.

**Fix**: Trim with `.whitespacesAndNewlines` before `saveAPIKey(...)`, matching the production flow.

**Test coverage added**: `test_provider_addTrimsAPIKeyWhitespace` — sends `"  sk-trim-me  \n"`, asserts the stored key is `"sk-trim-me"`.

**Docs updated**: `apiKey` parameter-validation entry in `docs/subsystems/debug-bridge.md` mentions the trim.

**Status**: fixed in round 1, verified clean in round 2.

## Round 2 — verdict

> No findings in the round-1 fixes. The updated parser, handler, tests, and docs are internally consistent.
>
> - `DebugCommand.swift:345` now enforces the same effective endpoint policy as the real add-provider flow.
> - `RealDebugBridgeContext+Provider.swift:81` reuses the existing UUID by `name`, so repeated `add` calls are idempotent and `remove(name:)` stays deterministic.
> - New parser tests cover the tightened endpoint cases; new handler regressions cover replace-by-name and key trimming.
> - Provider docs match the implementation.
>
> Residual risk (clear race) is unchanged and explicitly documented. Given the bridge's serialization model and the intended verification usage, that acceptance is reasonable.

## Final verdict

**ship-as-is**

## Test gate

- Focused: `xcodebuild test -only-testing:vreaderTests/DebugCommandTests -only-testing:vreaderTests/DebugBridgeTests -only-testing:vreaderTests/RealDebugBridgeContextTests` → 165 tests, 0 failures.
- Full `vreaderTests`: 1401 tests, 2 pre-existing flaky failures (`FoliateURLSchemeHandlerTests.testMIMETypeSVG()`, `SwiftDataSessionStoreTests.flushDurationUpdates()`) — both pass in isolation, same load-sensitive `Task.sleep`-then-assert pattern as Bug #230 / #236, unrelated to this change (the touched files are entirely under `vreader/Services/DebugBridge/` + `vreaderTests/Services/DebugBridge/`).

## Architectural notes worth preserving

- The `provider` command intentionally has NO bridge-specific `Notification.Name` (unlike `tts` / `search` / `highlight`). `ProviderProfileStore.shared.upsert/remove/setActiveProfileID` already post `.providerProfilesDidChange`, so any in-app picker / Settings VM resyncs without a duplicate DEBUG-only symbol. `DebugBridgeNotifications.swift` documents this explicitly.
- The handler depends on the actor-backed `ProviderProfileStore.shared` singleton in production. Tests inject a per-test `ProviderProfileStore(preferences:migrator:keychain:)` with `NoOpProviderProfileMigrator` + per-test UserDefaults suite + per-test Keychain `serviceIdentifier` for isolation. The shared-instance contract documented in `ProviderProfileStore.swift` (round-2 audit finding [2]) is preserved.
- Manual fallback was NOT needed — Codex MCP was available throughout both rounds.
