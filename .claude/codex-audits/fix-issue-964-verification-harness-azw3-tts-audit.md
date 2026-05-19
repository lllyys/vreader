---
branch: fix/issue-964-verification-harness-azw3-tts
threadId: 019e4098-795b-7d00-b6c7-c29716c37463
rounds: 3
final_verdict: ship-as-is
date: 2026-05-19
---

# Codex Audit — Issue #964 (Bug #233): verification harness AZW3 TTS seed

## Scope

Bug #233 / GH #964: the XCUITest verification harness cannot drive AZW3/MOBI
TTS pause/resume CU-free, blocking feature #57's `VERIFIED` close. Fix takes
**route (a)** from the bug row (the "more reusable" option): add an
`azw3Fixture` `TestSeedState` + `--seed-azw3-fixture` launch arg + an app-side
`seedMiniAZW3` handler, mirroring the existing `epubFixture` / `seedMiniEPUB`
wiring (Bug #214). DEBUG/test-only — never compiled into Release.

Route (b) — extending `DebugCommand.tts` to accept `pause`/`resume` — was
rejected for this PR: its consumer (`ReaderContainerView.swift:331` `.onReceive`)
is in feature agent #62's active write-set, which would violate rule 48's
one-writer-per-file invariant. Route (a)'s files (`VReaderApp.swift`,
`TestSeeder.swift`, `LaunchHelper.swift`) are disjoint from all three in-flight
feature agents (#58/#62/#64).

## Files audited

- `vreader/App/VReaderApp.swift` — `TestLaunchConfig.seedAZW3Fixture` field +
  `parse` + `.none`; `config.seedAZW3Fixture` added to the disk-backed-store
  whitelist and the seed dispatch chain.
- `vreader/App/TestSeeder.swift` — new `seedMiniAZW3(persistence:)`.
- `vreaderUITests/Helpers/LaunchHelper.swift` — `azw3Fixture` `TestSeedState`
  case + `--seed-azw3-fixture` launch argument.
- `vreaderTests/App/LaunchArgParsingTests.swift` — 6 new parser tests.
- `vreaderTests/App/TestSeederAZW3FixtureTests.swift` — NEW: 5 tests for
  `seedMiniAZW3`.

## Round 1

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `TestSeeder.swift` `seedMiniAZW3` | Medium | Backing-file writes (`createDirectory`, `data.write(to:)`) used `try?`, so the seed could insert a `BookRecord` with no backing file — recreating the "AZW3 row exists but the Foliate reader can't open it" failure mode the seed is meant to avoid. | **Fixed.** Writes are now checked inside a `do/catch`; on failure the seed logs `AppLogger.general.warning(...)` and `return`s before `insertBook`. Added test `seedMiniAZW3WritesBackingFileToDisk`. |
| `VReaderApp.swift` seed dispatch | Low | Seed selection is not mutually exclusive — `TestLaunchConfig.parse` sets independent booleans and the `else if` dispatch chain silently resolves `--seed-epub-fixture` + `--seed-azw3-fixture` together by picking EPUB. | **Fixed (document + pin).** Enforcing single-seed-mode is a property of the whole seed system (every existing seed flag shares it) — out of scope for this bug fix. Instead: `LaunchHelper.swift`'s `azw3Fixture` doc comment now states `TestSeedState` is a single enum value (so `launchApp(seed:)` picks exactly one seed) and documents the downstream `else if` EPUB-wins precedence; new parser test `bothFixtureFlagsSetBothBooleans` pins the behavior. Conflict is now documented + test-pinned, not silent. |

## Round 2

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `TestSeederAZW3FixtureTests.swift` `seedMiniAZW3WritesBackingFileToDisk` | Medium | The round-1 test was not isolated from prior runs: `clearAllBooks()` deletes only SwiftData rows, not `ImportedBooks/` files, and the seed writes to a deterministic path (fixed hash literal). A stale `mini-azw3` file from an earlier run could make the test pass even if the current seed never wrote the file — masking a write-path regression. | **Fixed.** The test now seeds once to learn the live file path, `removeItem`s that file and asserts it is absent (precondition `#expect`), then re-seeds and asserts the file exists. The load-bearing assertion can only pass if the post-delete re-seed re-created the file. The confusing dead-`fingerprint` helper from the first draft was replaced by `importedBooksDirectory()`. |

## Round 3

No findings. Codex confirmed the round-2 isolation fix is correct and the whole
#964 diff is clean — `VReaderApp` wiring, `seedMiniAZW3` fail-closed write
handling, `LaunchHelper` precedence documentation, and both new test suites.

## Manual audit evidence (test execution)

Codex performed a read-only audit and did not execute tests in its sandbox.
Test execution was done by this agent:

- `xcodebuild test -only-testing:vreaderTests/LaunchArgParsingTests -only-testing:vreaderTests/TestSeederAZW3FixtureTests` →
  **27 tests passed** (after the round-1 fixes; the round-2 fix re-verified
  with `TestSeederAZW3FixtureTests` → 4 tests passed; full suite gate run
  separately — see PR Validation section).
- RED was confirmed before GREEN: the pre-implementation build failed to
  compile because `config.seedAZW3Fixture` and `TestSeeder.seedMiniAZW3` did
  not exist (27 SwiftCompile failures).
- `DebugFixtureCatalogTests.test_all_entriesResolveInTheTestBundle` passes,
  confirming `mini-azw3.azw3` is genuinely present in the DEBUG test bundle so
  `seedMiniAZW3` resolves its resource at runtime.

## Summary verdict

**ship-as-is.** Three audit rounds, all findings (1 Medium + 1 Low in round 1,
1 Medium in round 2) fixed. DEBUG/test-only harness change with no Release
impact; mirrors the established `seedMiniEPUB` / `epubFixture` pattern with the
backing-file write hardened beyond the EPUB original.
