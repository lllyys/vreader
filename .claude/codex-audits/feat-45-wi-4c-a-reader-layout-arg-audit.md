---
branch: feat/45-wi-4c-a-reader-layout-arg
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-13
---

## Codex MCP availability test

`mcp__plugin_codex-toolkit_codex__codex` returned
`stream disconnected before completion: error sending request for url
(https://chatgpt.com/backend-api/codex/responses)` (third consecutive
attempt in today's session). Auditor genuinely unavailable, not
inconvenient. Manual audit per rule 47.

## Manual audit evidence

### Files read

- `vreader/App/VReaderApp.swift` (lines 85-160 + 313-460) — full
  `TestLaunchConfig` struct, parser, init-time DEBUG block.
- `vreader/Services/ReaderSettingsStore.swift` (lines 14, 21, 53, 58, 83)
  — `epubLayoutKey = "readerEPUBLayout"`, lazy load via `loadEPUBLayout`.
- `vreader/Models/EPUBLayoutPreference.swift` (lines 15-19) — enum cases
  `scroll` / `paged` with matching rawValues.
- `vreaderTests/App/LaunchArgParsingTests.swift` (new file, 8 cases).
- `vreaderUITests/Helpers/LaunchHelper.swift` (lines 96-211) — 3 entry
  points (`LaunchHelper.launchApp`, `vreaderUITests_launchApp`, free
  `launchApp`) all parameterized with `extraLaunchArguments: [String] = []`.
- `vreaderUITests/Helpers/TestConstants.swift` (lines 186-207) — new
  `LaunchArgs` enum with `readerLayoutPaged` / `readerLayoutScroll`.
- `vreaderUITests/Verification/Feature31AutoPageTurnVerificationTests.swift`
  — setUp now passes `extraLaunchArguments: [LaunchArgs.readerLayoutPaged]`;
  3-way Picker lookup removed.
- `dev-docs/plans/20260513-feature-45-verification-harness-sweep.md` —
  WI-4c plan + Gate 2 audit revision 2 (the plan that drove this WI).

### Symbols / signatures verified

- `TestLaunchConfig` struct boundary: `#if DEBUG` at line 324, `#endif` at
  line 474 — new `defaultEPUBLayout: EPUBLayoutPreference?` field correctly
  inside the DEBUG-only struct. ✓
- `EPUBLayoutPreference(rawValue: "paged")` → `.paged`,
  `EPUBLayoutPreference(rawValue: "scroll")` → `.scroll`,
  `EPUBLayoutPreference(rawValue: "garbage")` → `nil`. Verified by
  reading the enum cases. ✓
- `ReaderSettingsStore.epubLayoutKey` is `public static let` (accessible
  from VReaderApp's init). ✓
- The new UserDefaults write at VReaderApp:138-150 runs:
  - AFTER `if config.seedResetPreferences { TestSeeder.clearKnownPreferences() }`
    so reset doesn't wipe the override. ✓
  - INSIDE `if config.isUITesting` so production launches are unaffected. ✓
  - BEFORE any seed task / ViewModel construction, so `ReaderSettingsStore`
    reads the seeded value on first `init(defaults:)` call. ✓
- `args.append(contentsOf: extraLaunchArguments)` placed AFTER all
  helper-controlled flags but BEFORE `app.launchArguments = args` in
  `vreaderUITests_launchApp`. ✓
- All 3 entry points in `LaunchHelper.swift` carry the new parameter
  with identical default `[]`. ✓

### Edge cases checked

| Case | Behavior | Test |
|---|---|---|
| `--reader-default-layout=paged` | UserDefaults gets `"paged"` → store reads `.paged` | `parsesPagedLayout` |
| `--reader-default-layout=scroll` | UserDefaults gets `"scroll"` → store reads `.scroll` | `parsesScrollLayout` |
| `--reader-default-layout=garbage` | Falls through to nil → no UserDefaults write → store uses persisted/default | `invalidLayoutValueFallsThroughToNil` |
| `--reader-default-layout=` (empty value) | Empty rawValue → enum init fails → nil | `emptyLayoutValueFallsThroughToNil` |
| `--reader-default-layout` (no `=` suffix) | hasPrefix check requires `=`; the bare arg fails the check → nil | `bareFlagWithoutEqualsValueFallsThroughToNil` |
| Duplicate flag (two occurrences) | Last occurrence wins (loop overwrites) | `laterLayoutFlagWinsOverEarlier` |
| Flag with other seed flags | Coexists; no collisions | `layoutFlagCoexistsWithOtherSeedFlags` |
| No flag passed | `defaultEPUBLayout == nil` → no UserDefaults write → production default applies | `defaultEPUBLayoutIsNilWithoutFlag` |
| Flag without `--uitesting` | DEBUG block at line 121 is `isUITesting`-gated → UserDefaults write skipped → flag has no effect in non-test launches | implicit (covered by gate) |
| Production build (release) | All this code is `#if DEBUG`-gated → does not compile in Release | enforced by `verify-release-no-debugbridge.sh` gate |

### Risks accepted

- **R1 (Low)**: The Feature31 test's XCTSkip fallback at lines 91-98 is
  preserved (in case the section probe times out for an unrelated reason).
  This is intentional — defensive, not a silent failure path.
- **R2 (Low)**: `LaunchArgs` enum in `TestConstants.swift` uses
  hard-coded raw strings rather than a shared constant with VReaderApp.
  Accepted because the test target can't reach DEBUG-only declarations
  in the app target via `@testable`; the raw strings are pinned by the
  LaunchArgParsingTests anyway.
- **R3 (Low)**: No XCUITest run executed in this manual audit (audit is
  read-only). The Feature31 test refactor will be exercised by the
  device/integration verification gate (Gate 5) once a sim run lands.

### Tests added or intentionally deferred

- **Added**: `vreaderTests/App/LaunchArgParsingTests.swift` — 8 cases
  covering all parsing paths.
- **Deferred to WI-4c-b**: TTS autostart DebugBridge URL + Feature40/41
  test refactors. This WI ships JUST the layout-arg slice; TTS work is
  scoped separately because the spike-0 (DebugBridge URL handler + manual
  `simctl openurl` smoke check) hasn't been executed yet.

## Per-round findings

### Round 1

| # | Severity | Finding | Resolution |
|---|---|---|---|
| C1 | Medium | The parse loop iterates `arguments: [String]` (array) while the rest of `parse(_:)` uses `Set(arguments)`. Order preservation is required for "last occurrence wins" — array is correct. | Accepted as-is (already correct). |
| C2 | Low | No explicit test for `--reset-preferences + --reader-default-layout=paged` together; the implicit ordering is "reset wipes UserDefaults, THEN we write the layout key". Read VReaderApp:131-150 to confirm order. | Verified by code reading — reset runs at line 131, layout write runs at line 138-150. Order is correct. No test added (would duplicate existing TestSeederPreferencesTests coverage). |
| C3 | Low | No XCUITest run in this audit. | Accepted — Gate 5 (device verify) will run the Feature31 test against the new arg. |
| C4 | Low | The `import Testing` line in the new test file is the canonical Swift Testing import (vreader's primary framework per `.claude/rules/10-tdd.md`). | No action — matches project convention. |
| C5 | Low | `LaunchArgs.readerLayoutPaged` is a string constant. If `--reader-default-layout=` prefix changes in VReaderApp, the test constant won't auto-update. | Accepted — LaunchArgParsingTests pin the raw form `"--reader-default-layout=paged"` independently, so a parser-side change would break those tests AND the test constant; the constant is a convenience alias, not the source of truth. |

## Resolution

All 5 findings are Low/Medium with no Critical/High issues. C1 is
self-resolving (already correct). C2 is covered by code reading. C3
defers to Gate 5. C4–C5 are conventions or accepted trade-offs.

**Final verdict**: `ship-as-is`. The WI-4c-a slice is correct, narrowly
scoped, and consistent with the WI-4c plan (revision 2). TTS work is
explicitly deferred to a follow-up WI-4c-b per plan revision 2's spike-0
prerequisite.
