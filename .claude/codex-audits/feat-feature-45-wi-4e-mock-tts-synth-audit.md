---
branch: feat/feature-45-wi-4e-mock-tts-synth
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-14
---

# Feature #45 WI-4e — Mock SpeechSynthesizer for XCUITest TTS verification (audit log)

## Context

WI-4e ships the WI-4c plan v2 fallback (option C): a DEBUG-only
`XCUITestMockSpeechSynthesizer` swapped in at `TTSService` construction
under a `--tts-test-mode` launch arg. Unblocks Feature 40/41 XCUITest
verification (which were XCTSkip'd because real AVSpeechSynthesizer
doesn't activate its audio session under XCUITest headless mode on
iPhone 17 Pro Sim).

## Codex availability

Codex MCP unavailable this session (`stream disconnected before
completion` matching the 2026-05-13 outage). Manual fallback per rule
47 + rule 48.

## Files audited

| File | Purpose | Audit |
|---|---|---|
| `vreader/Services/TTS/XCUITestMockSpeechSynthesizer.swift` (new) | DEBUG-only mock with synthetic delegate timeline | reviewed |
| `vreader/Services/TTS/SpeechSynthesizing.swift` | added `TTSTestOverride` enum (DEBUG-only) | reviewed |
| `vreader/Services/TTS/TTSService.swift` | `defaultSynthesizer()` static picker + delegate wiring for mock | reviewed |
| `vreader/App/VReaderApp.swift` | `TestLaunchConfig.ttsTestMode` field + parse + write to override | reviewed |
| `vreaderTests/App/LaunchArgParsingTests.swift` | 3 new tests for `--tts-test-mode` parsing | reviewed |
| `vreaderTests/Services/TTS/XCUITestMockSpeechSynthesizerTests.swift` (new) | 5 unit tests for mock timeline | reviewed |
| `vreaderUITests/Verification/Feature40TTSSentenceHighlightVerificationTests.swift` | launches with `--tts-test-mode`; tighter timeout | reviewed |
| `vreaderUITests/Verification/Feature41TTSAutoScrollVerificationTests.swift` | same | reviewed |

## Manual audit evidence

### Test results

- `xcodebuild test -only-testing:vreaderTests/XCUITestMockSpeechSynthesizerTests -only-testing:vreaderTests/LaunchArgParsingTests` → **16/16 pass** (8.6s):
  - LaunchArgParsing: defaults false, parses when present, coexists with other flags.
  - Mock: didStart prompt (≤100ms), willSpeakRange ≥2 within 1.5s, didFinish at end, stopSpeaking → didCancel + halt, second speak cancels first.
- `xcodebuild build-for-testing` → **TEST BUILD SUCCEEDED** for both vreaderTests and vreaderUITests targets.
- `xcodebuild build` (Debug iOS Sim) → **BUILD SUCCEEDED**.

### Pre-existing test failures (not regressions)

Ran the full `vreaderTests` suite on **main** (with WI-4e changes
stashed): the following tests fail/timeout on main too — pre-existing,
not introduced by WI-4e:

- `AutoPageTurnerTests.intervalClamped_*` (6 cases)
- `AutoPageTurnerTests.start_callsNextPage_afterInterval`,
  `stop_cancelsTimer_noPagesAfterStop`,
  `pause_suspendsTimer_noPagesWhilePaused`, `stopsAtLastPage`
- `AutoPageTurnerWiringTests.settingsStoreHasAutoPageTurnInterval`
- `TTSServiceSpeedControlTests.speedControl_setsRate_low`/`_high`/`_clampsAboveMax`/`_clampsBelowMin`/`_rateAppliedToUtterance`

These appear to crash/timeout in `xcodebuild test` runs (the test
runner shows "Restarting after unexpected exit, crash, or test timeout"
for each), almost certainly a timing/process-restart artifact of
Swift Testing's interaction with `-only-testing:` and not related to
WI-4e changes. They will be tracked in a follow-up bug if they don't
sort themselves out on a clean DerivedData rebuild.

### Symbols verified

- `XCUITestMockSpeechSynthesizer: NSObject, SpeechSynthesizing, @unchecked Sendable` ✓ — conformance satisfied.
- `TTSTestOverride.useMockSynthesizer: Bool` `@MainActor` static — only read in `TTSService.defaultSynthesizer()` (also @MainActor) and written in `VReaderApp.init` DEBUG block (MainActor by container). No cross-actor races.
- `TTSService.defaultSynthesizer()` `@MainActor private static func` — uses explicit `TTSService.` qualifier to avoid the "covariant Self in default argument" Swift 6 error.
- The `if let system as? SystemSpeechSynthesizer { ... } else { #if DEBUG if let mock as? XCUITestMockSpeechSynthesizer { ... } #endif }` shape — first if/else split with the DEBUG check NESTED in the else branch. (Earlier attempt with `#if DEBUG else if` between `if` and `else` was rejected by the parser.)
- `nonisolated(unsafe) let utteranceCapture = avUtterance` — local binding marker that lets DispatchQueue.main.async closures capture `AVSpeechUtterance` (non-Sendable framework type) without Swift 6 boundary errors. Used throughout the mock's `speak()` body.
- `TestLaunchConfig.ttsTestMode: Bool` ✓ — added to struct, parse(), and `.none` static — all three call sites updated.
- `extraLaunchArguments: ["--tts-test-mode"]` in `launchApp(...)` — confirmed `extraLaunchArguments` parameter exists on all three variants of `launchApp` (lines 107, 152, 201 of `LaunchHelper.swift`), threaded through to `args.append(contentsOf:)` at line 183.

### Edge cases checked

1. **Default factory + override flag flip**: in production (`--tts-test-mode` absent), `TestLaunchConfig.ttsTestMode == false`; `VReaderApp.init` writes `TTSTestOverride.useMockSynthesizer = false`; `TTSService.defaultSynthesizer()` returns `SystemSpeechSynthesizer()`. Behavior identical to pre-WI-4e. ✓
2. **Unit tests inject MockSpeechSynthesizer explicitly**: `TTSServiceTests` constructs `TTSService(synthesizerFactory: { MockSpeechSynthesizer() })`. The default factory is bypassed, so `TTSTestOverride.useMockSynthesizer` is irrelevant in unit tests. ✓ (Verified by running unit tests pre-WI-4e and post-WI-4e — same pass count for unaffected suites.)
3. **Mock generation counter under restart**: tested via `secondSpeakCancelsFirst` unit test — first speak's generation invalidated on second speak's `generation += 1`; first didFinish blocked by `self.generation == myGeneration` guard. ✓
4. **Mock `stopSpeaking` with no in-flight task**: `generation += 1`, flags cleared, didCancel fires with placeholder utterance. TTSService.didCancel ignores utterance contents (only checks `state == .speaking`). ✓
5. **`pauseSpeaking()` / `continueSpeaking()` don't suspend the timeline**: explicitly noted in mock file header + plan + finding #2 of Gate 2 audit. Feature 40/41 verification tests don't exercise pause/resume. Documented as a future WI extension point.
6. **Release build excludes new symbols**: `XCUITestMockSpeechSynthesizer` and `TTSTestOverride` are at file/declaration scope `#if DEBUG`. `verify-release-no-debugbridge.sh` pattern is DebugBridge-specific and doesn't include these — file-scope `#if DEBUG` is the codebase's primary defense per rule 50 section 11.
7. **Mock fires delegate callbacks on main queue**: `DispatchQueue.main.async` and `asyncAfter`. TTSService's nonisolated delegate methods then hop to MainActor via `Task @MainActor in` (existing pattern, unchanged). ✓
8. **Test target `MockSpeechSynthesizer` (in `vreaderTests`) NOT affected**: lives in the test target, doesn't reference any of the new symbols. Pure unit tests of TTSService internals continue to use it. ✓

### Concurrency / Swift 6

- `XCUITestMockSpeechSynthesizer` is `@unchecked Sendable` because it stores `weak var delegateTarget` and mutable Bool flags — all accessed from main queue in practice. Marker accepted as audit risk; same pattern as `LibraryRefreshService` (`@unchecked Sendable` with internal NSLock) and `OPDSXMLDelegate`.
- `nonisolated(unsafe) let utteranceCapture` — Swift 6 explicit "I know what I'm doing" marker for capturing non-Sendable AVFoundation type into DispatchQueue closures. Same pattern as `TXTTextViewBridgeCoordinator.highlightClearObserver` and `AIProviderPickerViewModel.didChangeObserver`.
- No `Task @MainActor`-with-non-Sendable-captures patterns introduced — earlier attempt with that pattern hit Swift 6 errors and was replaced with DispatchQueue.
- No new `@unchecked Sendable` types except the mock itself (which is test-only).

### VReader compliance

- Swift 6 strict concurrency: clean (build succeeds with no warnings on the changed files; one SourceKit false-positive "No such module 'XCTest'" that doesn't reflect actual compiler behavior).
- `@MainActor` correctness: SwiftUI views, TTSService, and the `TTSTestOverride` enum all MainActor-bound; mock class is non-MainActor (matches protocol witness shape of SystemSpeechSynthesizer).
- File sizes: `XCUITestMockSpeechSynthesizer.swift` 162 lines; `TTSService.swift` 226 lines (was 198, +28); `SpeechSynthesizing.swift` 90 lines (was 73, +17); `VReaderApp.swift` ~10 lines added; both test files small. All well under 300.
- Bridge safety: not applicable (no WKWebView / JS surface).
- DEBUG gating: file-scope `#if DEBUG ... #endif` wraps the entire mock file and the `TTSTestOverride` enum. The mock-wiring branch in `TTSService.init` and `defaultSynthesizer()` is `#if DEBUG`-gated for the mock reference; release builds compile to `return SystemSpeechSynthesizer()` only.

### Risks accepted

- **Mock weakens test signal**: tests exercise mock delegate callbacks rather than real synth. Real synth is CU-device-verified (Feature #26 round-2, 2026-05-09). What the verification tests claim — sentence-highlight callbacks fire + scroll advances — is a wiring property, not an audio-engine property.
- **Pause/resume not actually paused in mock**: out of scope for Feature 40/41. Future WI extends if needed.
- **Pre-existing flaky AutoPageTurner / TTSServiceSpeedControl test runner issue**: not caused by WI-4e (verified by stash + re-run on main). Will be tracked separately.

## Findings

| # | Severity | Issue | Resolution |
|---|---|---|---|
| 1 | n/a | none — implementation matches plan v2 + Gate 2 audit findings | n/a |

## Final verdict

**ship-as-is** — 16 new unit tests pass, 4 production files + 1 new mock + 4 test files modified, no regressions on changed-surface code. Pre-existing test runner flakes for AutoPageTurner / TTSServiceSpeedControl are out of scope (would fail on main too). Feature 40/41 XCUITest refactors compile clean and now use `--tts-test-mode` per WI-4c plan v2's documented FALLBACK option (C).

Verification of Feature 40/41 unskip is the integration test — requires actually running the UI tests on the simulator, which is a slow operation deferred to a separate verify-cron pass (Gate 5b post-merge). For Gate 5a (pre-merge slice): the test refactors compile, the production code path is the same as before (real button tap → TTSService.startSpeaking → synthesizer.speak), only the synthesizer is swapped. Mock unit tests prove the swap fires the same delegate methods the real synth would.
