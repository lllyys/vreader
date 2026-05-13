---
branch: feat/45-wi-4c-c-tts-snapshot-wiring
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-13
---

## Context

Feature #45 WI-4c-c implementation audit. Codex MCP unavailable this session (every call returns `stream disconnected before completion: error sending request for url (https://chatgpt.com/backend-api/codex/responses)`). Manual fallback per rule 47.

## Files in scope

- `vreader/Services/DebugBridge/DebugReaderProbeAdapter.swift` (+16 lines)
- `vreader/Services/DebugBridge/RealDebugBridgeContext+Snapshot.swift` (+18 / −7 lines)
- `vreader/Views/Reader/ReaderContainerView.swift` (+13 lines)
- `vreaderTests/Services/DebugBridge/DebugReaderProbeAdapterTests.swift` (new, +68 lines)
- `vreaderTests/Services/DebugBridge/RealDebugBridgeContextTests.swift` (+57 / −5 lines)
- `dev-docs/plans/20260513-feature-45-verification-harness-sweep.md` (+109 lines: WI-4c-c plan addendum + Gate 2 audit evidence)

## Manual audit evidence

### Files read

- All 6 files in scope.
- Verified prior-art precedent: `DebugReaderProbeAdapter.positionProvider` (existing closure pattern matching mine).
- Verified protocol shape: `DebugReaderProbe.currentTTSState` / `currentTTSOffsetUTF16` at `DebugReaderRegistry.swift:54-58` with default-nil impls at lines 74-79.
- Verified wire-value constants: `DebugSnapshot.TTSStateValue.{idle,speaking,paused}` at `DebugSnapshot.swift:77-81`.
- Verified `TTSService.State.publicName` extension at `DebugReaderRegistry.swift:84-92`.
- Verified `TTSService` isolation: `@MainActor @Observable final class` at `TTSService.swift:19-20`.
- Verified `TTSService.currentOffsetUTF16 = 0` on `.idle` (after `stop()` at `TTSService.swift:146`).

### Symbols / signatures verified

- `DebugReaderProbeAdapter.ttsProbe: (@MainActor () -> (state: String, offsetUTF16: Int?))?` — exact closure shape used by `ReaderContainerView` call site. Confirmed compile via test run.
- `currentTTSState` and `currentTTSOffsetUTF16` overrides correctly shadow protocol defaults.
- `DebugSnapshot.init(..., ttsState: String? = nil, ttsOffsetUTF16: Int? = nil, settingsProvenance: String? = nil)` — last three are defaulted; my new call passes `ttsState` + `ttsOffsetUTF16` and leaves `settingsProvenance` nil (correct — feature #50 owns it).
- `Set` equality assertions in snapshot tests — order-insensitive, robust.

### Per-dimension findings

**1. Correctness vs the plan.** Plan acceptance criteria 1-6 all delivered:
- ✓ AC1: `ttsProbe` closure added; default nil preserves protocol default.
- ✓ AC2: `ReaderContainerView.onAppear` wires closure (DEBUG-only `.onAppear` block).
- ✓ AC3: snapshot passes `probe?.currentTTSState`/`currentTTSOffsetUTF16` to init; partial array updated for both new fields + always-partial `settingsProvenance`.
- ✓ AC4: 5 new adapter tests + 1 new snapshot test cover with-closure / without-closure paths.
- ✓ AC5: 3 existing snapshot tests updated for new partial-array members.
- ✓ AC6: targeted suites green (RealDebugBridgeContextTests 35/35, DebugReaderProbeAdapterTests 5/5).

**2. Edge cases.** Walked:
- TTS idle state → closure returns `(state: "idle", offsetUTF16: nil)`. Snapshot writes `ttsState: "idle"` and adds `ttsOffsetUTF16` to partial. Correct: offset is meaningless at idle (`currentOffsetUTF16 = 0` from stop).
- TTS speaking with offset 0 (first frame before delegate callback) → `(state: "speaking", offsetUTF16: 0)`. Both fields present, neither partial. Consumer can distinguish via state == "speaking" + offset == 0 ("just started").
- TTS paused mid-read → `(state: "paused", offsetUTF16: N)`. Both populated. Correct.
- No probe registered → `probe == nil` branch executes; ttsState/ttsOffsetUTF16 also added to partial. Correct.
- Probe registered with no ttsProbe (e.g., test fixture) → `probe?.currentTTSState` returns nil via `ttsProbe?().state` → both fields added to partial. Correct, covered by `test_snapshot_withActiveReader_populatesReaderFieldsAndShrinksPartial`.
- Probe registered with ttsProbe → both fields populated, dropped from partial. Correct, covered by new `test_snapshot_withTTSProbeWired_populatesTTSFieldsAndShrinksPartial`.

**3. Security.** No JS interpolation, no user input, no network. N/A.

**4. Duplicate code.** None. Closure mirrors existing `positionProvider` precedent. Partial-array conditional `if X == nil { partial.append("X") }` matches the existing position handling pattern.

**5. Dead code.** None.

**6. Shortcuts & patches.** None. `settingsProvenance` always-partial is documented as a deliberate audit-driven decision (Gate 2 finding #4), not a shortcut.

**7. VReader compliance.**
- Swift 6 concurrency: closure annotated `@MainActor`. Closure captures `service: TTSService` which is itself `@MainActor`. Both ends agree.
- `@MainActor` correctness: closure called via `currentTTSState` (a non-isolated `var`) on adapter which is `@MainActor`. Protocol member is on `@MainActor` protocol. All call sites respect isolation.
- File-size budget:
  - `DebugReaderProbeAdapter.swift`: 76 → 92 lines (well under 300).
  - `RealDebugBridgeContext+Snapshot.swift`: 92 → 104 lines (well under 300).
  - `ReaderContainerView.swift`: +13 lines (existing file pre-WI-4c-c was ~550; not in this WI's scope to split).

**8. Bridge safety.** Not bridge code. N/A.

### Lifecycle / retain-cycle analysis

The closure pattern is:
```
let service = ttsService            // captures the @State TTSService class ref
probe.ttsProbe = { @MainActor in    // closure stored on probe (strong)
    let state = service.state       // strong ref to service inside closure
    ...
}
debugProbe = probe                  // probe stored on view (@State, strong)
DebugReaderRegistry.shared.register(probe)  // registry holds WEAK ref
```

Strong-ref graph: View → debugProbe → ttsProbe closure → service. View also owns ttsService directly (the closure is a second strong ref). On `.onDisappear`:
1. `DebugReaderRegistry.shared.unregister(probe)` — drops weak ref.
2. `debugProbe = nil` — drops the View's strong ref to probe → closure dies → second strong ref to service dies. View's @State ttsService still owned until view tears down.

No retain cycles (service does not reach back into the probe or the closure). Safe.

### Concurrency analysis

- Closure declared `@MainActor`. Adapter's `currentTTSState`/`currentTTSOffsetUTF16` accessors are non-isolated `var`s on a `@MainActor` class — accessing them from non-MainActor code would fail to compile. Snapshot path goes through `RealDebugBridgeContext.snapshot(...)` which is `async` — verified call site reads `probe?.currentTTSState` (line 32 in extension). `probe` is `DebugReaderRegistry.shared.current` which is `@MainActor`-isolated. The read must happen on MainActor; closure runs there. Single hop.
- No data races: closure reads from `@MainActor @Observable TTSService` fields under MainActor isolation.

### Risks accepted

- `settingsProvenance` always in `partial` until feature #50 wires per-format hosts. Documented; consumers treat partial-listed fields as "not authoritative."

### Tests added or intentionally deferred

- 5 new adapter unit tests (with/without closure × state/offset × idle-case).
- 1 new snapshot end-to-end test (`test_snapshot_withTTSProbeWired_populatesTTSFieldsAndShrinksPartial`).
- 3 existing snapshot tests updated for new partial-array members.
- None deferred.

### Test gate

```
xcodebuild test -only-testing:vreaderTests/DebugReaderProbeAdapterTests
→ 5/5 passed in 0.003s
xcodebuild test -only-testing:vreaderTests/RealDebugBridgeContextTests
→ 35/35 passed in 1.112s
```

Pre-existing flake: `TXTChapterHighlightRenderingTests` crash on `highlights from ch0 are dropped when rendering ch2`. Reproduced on clean `main` (commit be51d7d) with this branch stashed → filed as bug #174 (GH #598). Pre-existing flakes `AutoPageTurnerTests.stopsAtLastPage` and `TTSServiceSpeedControlTests` under load — same class of pre-existing flakes that bug #167's close-gate note flagged on its full-suite run. Not introduced by WI-4c-c.

## Verdict

**ship-as-is** (manual fallback verdict, 1 round).

All acceptance criteria met. Targeted test gates green. No findings against the diff. No retain cycles. No concurrency violations. No security surface. File-size budget intact.
