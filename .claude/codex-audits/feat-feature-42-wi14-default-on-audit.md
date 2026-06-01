---
branch: feat/feature-42-wi14-default-on
threadId: codex-exec-gpt-5.5-20260601
rounds: 1
final_verdict: ship-as-is
date: 2026-06-01
---

# Codex Audit — Feature #42 WI-14 (Readium default-ON flip)

## Scope

Human-gated G2 sign-off (2026-06-01) to flip `FeatureFlags.readiumEPUBEngine`
default from OFF → ON, making the Readium Swift Toolkit navigator the default
reflowable EPUB engine (legacy `EPUBWebViewBridge` reachable via a persisted
override OFF).

Files reviewed:
- `vreader/Services/FeatureFlags.swift` — `case .readiumEPUBEngine:` default
  `return false` → `return true` (+ doc).
- `vreaderTests/Services/FeatureFlagsTests.swift` — `…DefaultsOnInAllEnvironments`
  (was `…Off`), `…OverrideCanDisable` (was `…Enable`).

## Audit focus

(1) flip correctness + completeness (no other place hardcodes the OFF default);
(2) the updated tests pin the new ON default + override-disable + removeOverride-
restores-default; (3) persisted-override interaction (no-override user now gets
ON; a persisted false still wins); (4) Swift correctness.

## Round 1 — findings

Codex (gpt-5.5, read-only sandbox). **Behavior verdict: the flip is correct** —
`defaultValue` returns true, no override means ON, a persisted `false` still
wins. Swift logic sound. 4 Low findings (all resolved):

| # | file:line | sev | issue | resolution |
|---|---|---|---|---|
| 1 | FeatureFlags.swift:33 | Low | enum doc still said "Default OFF" | FIXED — doc updated to default-ON-since-WI-14 |
| 2 | FeatureFlags.swift:155 | Low | accessor doc still said default OFF | FIXED — doc updated |
| 3 | ReaderContainerView.swift:965 | Low | dispatcher comment said "default OFF → EPUBReaderHost stays the live default" | FIXED — comment updated to default-ON / persisted-OFF-override |
| 4 | FeatureFlagsTests.swift:166 | Low | override-disable test covers runtime removal but not the PERSISTED OFF path | FIXED — added `readiumEPUBEngineOverridePersists` (persisted false survives reload, beats ON default; removeOverride restores ON) mirroring `epubContinuousScrollOverridePersists` |

## Test evidence

- `vreaderTests/FeatureFlagsTests` + `vreaderTests/ReaderEngineTests` +
  `vreaderTests/ReaderContainerViewEngineDispatchTests` green.
- 9 core Readium-engine suites green (ReadiumOpenSmoke, ViewModel, Nav/Pref
  mapping, Decoration/SelectionHighlight, DebugProbe, Host).
- New: `readiumEPUBEngineDefaultsOnInAllEnvironments`,
  `readiumEPUBEngineOverrideCanDisable`, `readiumEPUBEngineOverridePersists`.

## Summary verdict

ship-as-is (all 4 Low findings fixed).
