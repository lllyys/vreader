---
branch: feat/feature-72-wi-1-config-store
threadId: 019e639b-b8ca-71b3-b32a-6c494a5daecf
rounds: 1
final_verdict: ship-as-is
date: 2026-05-26
---

# Codex audit — Feature #72 WI-1 (HTTPTTSConfigStore loader)

Gate-4 audit (Codex MCP) of WI-1: centralized loader for the persisted HTTP
cloud-TTS config (UserDefaults `httpTTSConfig` + Keychain
`com.vreader.httpTTS.apiKey`) behind a testable seam.

Files: `HTTPTTSConfigStore.swift` (new), `HTTPTTSConfigStoreTests.swift` (new).

## Round 1 — clean (no findings)

Codex verified against the writer (`HTTPTTSSettingsView`):
- `configKey` + `keychainAccount` match exactly; the blank-apiKey-in-UserDefaults
  convention (key lives only in Keychain) is correctly mirrored.
- `HTTPTTSKeychainReading.readString(forAccount:)` matches
  `KeychainService.readString(forAccount:)`; the conformance seam is sound.
- `loadValidConfig()` correctly returns nil for unconfigured / invalid-endpoint /
  missing-keychain-key (→ empty apiKey → `validate()` rejects) cases.
- No Sendable/concurrency issue; tests use an isolated UserDefaults suite + stub
  keychain and cover the missing-key→invalid path.

## Verification

`HTTPTTSConfigStoreTests` — 6 tests pass (UDID-pinned, `-parallel-testing-enabled NO`).

## Verdict

**Ship-as-is.** No findings. Foundational loader; the WI-3 adapter selection
will consume `loadValidConfig()`.
