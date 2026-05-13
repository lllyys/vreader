---
branch: feat/45-wi-4c-b-tts-debugbridge
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-13
---

# Gate 4 Audit — Feature #45 WI-4c-b spike-0

**Codex MCP unavailable** (`stream disconnected before completion` on availability
ping at 2026-05-13 ~19:00 local — 4th disconnect this session). Manual fallback
per `.claude/rules/47-feature-workflow.md` Gate 4 + manual-fallback section.

## Scope

Diff under audit (per `git diff main --stat`):

```
 vreader/Services/DebugBridge/DebugBridge.swift           |  8 +++++
 vreader/Services/DebugBridge/DebugBridgeNotifications.swift | 14 +++++++++
 vreader/Services/DebugBridge/DebugCommand.swift          | 17 ++++++++++
 vreader/Services/DebugBridge/RealDebugBridgeContext.swift   | 18 +++++++++++
 vreader/Views/Reader/ReaderContainerView.swift           | 21 +++++++++++++
 vreaderTests/Services/DebugBridge/DebugBridgeTests.swift     |  3 ++
 vreaderTests/Services/DebugBridge/DebugCommandTests.swift    | 36 +++++++++++++++
 7 files changed, 117 insertions(+)
```

Plus plan + evidence (non-Swift):
- `dev-docs/plans/20260513-feature-45-verification-harness-sweep.md` — appended WI-4c-b spike-0 verdict.
- `dev-docs/verification/artifacts/feature-45-wi-4c-b-tts-{start,stop}-spike0-20260513.png` — spike-0 screenshots.

## Manual Audit Evidence

### Files read (full)

- `vreader/Services/DebugBridge/DebugCommand.swift` (post-change)
- `vreader/Services/DebugBridge/DebugBridge.swift` (post-change)
- `vreader/Services/DebugBridge/DebugBridgeNotifications.swift` (post-change)
- `vreader/Services/DebugBridge/RealDebugBridgeContext.swift` (post-change)
- `vreader/Services/DebugBridge/RealDebugBridgeContext+Snapshot.swift` (read for ttsState wire context)
- `vreader/Services/DebugBridge/DebugSnapshot.swift` (lines naming ttsState/ttsOffsetUTF16)
- `vreader/Services/DebugBridge/DebugReaderProbeAdapter.swift`
- `vreader/Views/Reader/ReaderContainerView.swift` (post-change, including DEBUG observer block)
- `vreader/Views/Reader/ReaderContainerView+Sheets.swift` (startTTS implementation)
- `vreader/Services/TTS/TTSService.swift` (state machine, startSpeaking, stop)
- `vreaderTests/Services/DebugBridge/DebugBridgeTests.swift` (mock conformers)
- `vreaderTests/Services/DebugBridge/DebugCommandTests.swift` (new tts cases)

### Symbols / signatures verified

| Symbol | Verified to exist | Where |
|---|---|---|
| `DebugCommand.tts(action: String)` | YES — new enum case | DebugCommand.swift:36 |
| `DebugCommandError.invalidParam(_, reason:)` | YES, pre-existing | DebugCommand.swift:49 |
| `DebugBridgeContext.tts(action:) async throws` | YES — new protocol requirement | DebugBridge.swift:35 |
| `DebugBridge.dispatch` switch covers `.tts` | YES | DebugBridge.swift:149-150 |
| `Notification.Name.debugBridgeTTSCommand` | YES, `#if DEBUG`-gated | DebugBridgeNotifications.swift:47 |
| `RealDebugBridgeContext.tts(action:)` | YES — new method | RealDebugBridgeContext.swift:259 |
| `TTSService.startSpeaking(text:fromOffset:)` | YES | TTSService.swift:70 |
| `TTSService.stop()` | YES | TTSService.swift:143 |
| `TTSService.State` enum cases | `idle`, `speaking`, `paused` — all exist | TTSService.swift:24-28 |
| `ReaderContainerView.startTTS()` | YES — used as start path | ReaderContainerView+Sheets.swift:17 |
| `ReaderContainerView.ttsService` | YES, `@State` | ReaderContainerView.swift:57 |
| `SlowDebugBridgeContext.tts` stub | YES — added | DebugBridgeTests.swift:185 |
| `RecordingDebugBridgeContext.tts` stub | YES — added | DebugBridgeTests.swift:222 |
| `RecordingDebugBridgeContext.Call.tts` enum case | YES — added | DebugBridgeTests.swift:202 |

No model-assumption mismatches — every symbol the new code references was verified
against the post-change file.

### Edge cases checked

| # | Edge case | Handling | Verdict |
|---|---|---|---|
| 1 | Empty action `?action=` | `requireParam` rejects empty | OK (covered by existing `test_parse_ttsMissingAction_throwsMissingParam`) |
| 2 | Missing action param `?` | `requireParam` throws `missingParam("action")` | OK |
| 3 | Unknown action `?action=play` | `guard action == "start" \|\| action == "stop"` throws `invalidParam` | OK (covered by `test_parse_ttsInvalidAction_throwsInvalidParam`) |
| 4 | Action case sensitivity `?action=START` | Rejected — string comparison is exact | OK — matches existing `theme?mode=` shape |
| 5 | Duplicate action param `?action=start&action=stop` | `queryParams` already rejects duplicates with `invalidParam` for any key | OK (pre-existing protection) |
| 6 | URL-encoded action `?action=%73tart` | Foundation decodes before parser sees it | OK (inherits from `URLComponents`) |
| 7 | Trailing slash `vreader-debug://tts/?action=start` | Parser allows `path == "/"` | OK |
| 8 | Stray path `vreader-debug://tts/extra?action=start` | Parser rejects with `unknownCommand` | OK (pre-existing protection) |
| 9 | Start fired when already speaking | Observer guards: `if ttsService.state == .idle` | OK — idempotent no-op, matches "succeed but no-op when already in target state" posture |
| 10 | Stop fired when already idle | Observer guards: `if ttsService.state != .idle` | OK — idempotent no-op |
| 11 | URL fired with no reader presented | Observer doesn't fire (ReaderContainerView not in view hierarchy) | OK — matches `.theme` shape (URL succeeds at bridge layer; live view applies if present) |
| 12 | Two reader instances stacked (rare) | Both observers fire; both call `startTTS()` on their own `@State`-owned `ttsService` | DOCUMENTED — only the top reader is user-visible, but if a stacked instance also responds, it's a no-op or harmless duplicate. Acceptable for a debug-only path. |
| 13 | Concurrent URLs `vreader-debug://tts?action=start` fired twice rapidly | `DebugBridge.handle` serializes via pendingTask chain; observer's `state == .idle` guard idempotent on second fire | OK |
| 14 | Start → Stop → Start → Stop sequence | TTSService already handles restart via generation counter; observer state guards ensure correct routing | OK |
| 15 | TTS service init failure (no AVAudioSession) | `startSpeaking` doesn't throw — state may remain .idle. Observer doesn't observe failure (no completion handler). | DOCUMENTED — surfaces via `snapshot.ttsState` once Feature #40 wires that in (currently nil-only). Acceptable for spike-0; the success path is the spike's deliverable. |

### Security

- **No JS evaluation** — handler posts a Notification only; no `evaluateJavaScript`.
- **No filesystem writes** — no snapshot, no file output.
- **No string interpolation into shell / HTML / SQL / JS** — the action string is logged via OSLog with `privacy: .public`, but it's restricted to the alphabet `{"start","stop"}` by the parser, so the public log can never leak user data.
- **#if DEBUG gating** — `DebugCommand.tts`, `DebugBridgeContext.tts`, `Notification.Name.debugBridgeTTSCommand`, `RealDebugBridgeContext.tts`, and the `ReaderContainerView` observer block are all within `#if DEBUG` extension files or `#if DEBUG ... #endif` blocks. Release builds cannot reach this path. (`verify-release-no-debugbridge.sh` would catch a regression.)
- **No external input reaches sensitive code** — `action` is parsed and validated by `DebugCommand.parse` before reaching the production startSpeaking call. The parser is the only entrance.

### Duplicate / dead code

- No duplicate handlers introduced — `tts` dispatch routes to a single context method like every other command.
- No dead code — every new line is reached by either a test (parser cases) or the production URL handler (verified by spike-0 smoke test).
- Reused `startTTS()` rather than reimplementing the load-text-then-speak path, so there's no parallel implementation to drift. This was a deliberate choice flagged in the commit message because the property under test is "real user-tap path activates audio."

### VReader compliance

- **Swift 6 concurrency**: protocol method is `@MainActor func tts(action:) async throws`; implementation matches. Observer closure runs on main (NotificationCenter publisher emits on registration queue; we registered on `.main`).
- **`@MainActor` correctness**: all new code is inside `@MainActor` types/protocols.
- **File size budget**:
  - DebugCommand.swift: 207 → 223 lines (under 300 ✓)
  - DebugBridge.swift: 154 → 155 lines (under 300 ✓)
  - DebugBridgeNotifications.swift: 41 → 54 lines (under 300 ✓)
  - RealDebugBridgeContext.swift: 254 → 271 lines (under 300 ✓)
  - ReaderContainerView.swift: 499 → 520 lines (over 300 — **pre-existing condition**; this WI adds 21 lines on a file that has been over budget for a while. Splitting ReaderContainerView is a separate concern, not in spike-0 scope.)
- **Bridge safety**: no JS interpolation, no WKWebView messages.
- **OSLog**: uses the existing `log` instance with `privacy: .public` only on the validated action string.

### Tests added or intentionally deferred

**Added (all green):**
- `DebugCommandTests.test_parse_ttsStartAction_returnsTtsStart` — parse start.
- `DebugCommandTests.test_parse_ttsStopAction_returnsTtsStop` — parse stop.
- `DebugCommandTests.test_parse_ttsMissingAction_throwsMissingParam` — missing param.
- `DebugCommandTests.test_parse_ttsInvalidAction_throwsInvalidParam` — invalid alphabet.

Suite results:
- `vreaderTests/DebugCommandTests`: 40/40 pass.
- `vreaderTests/DebugBridgeTests`: pass.
- `vreaderTests/RealDebugBridgeContextTests`: pass.

**Deferred (with rationale):**
- **Dispatcher routing test** — `DebugBridgeTests` already covers each existing command via `RecordingDebugBridgeContext`. A `test_handle_tts_dispatchesContextTTSCalled` would be a one-liner add; deliberately skipped at spike-0 because the routing shape is identical to every existing command (switch case → `await context.foo(...)`). If we accumulate more dispatcher cases, this gap should close — flagged for the WI-4c-b follow-up if Feature #40/#41 tests need stronger guarantees.
- **Observer integration test** — XCUITest in `vreaderUITests/` can drive the URL after opening a book, but adding the test as part of spike-0 would conflate "does the URL handler work" with "does the XCUITest harness call it correctly." Spike-0's purpose is the former; the latter is the next WI (Feature #40 / #41 test refactor).
- **Snapshot ttsState wiring** — `RealDebugBridgeContext+Snapshot.swift` hardcodes `ttsState: nil`. Surface area for Feature #40 verification requires populating `ttsState` from `DebugReaderRegistry.shared.current` (with a `ttsStateProvider` closure on the probe adapter, parallel to `positionProvider`). Plan v2 risk #5 already names this as Feature #40's dependency; not a spike-0 task.

### Risks accepted (with rationale)

1. **ReaderContainerView.swift now 520 lines** — over the 300-line guideline. Risk: ongoing maintenance load on this file. Accepted because: (a) splitting was already needed before this WI; (b) 21-line addition is consistent with the surrounding pattern (other `.onReceive` blocks in the same chain); (c) the alternative — moving the observer to its own extension — would force a `@State`-binding workaround that obscures the simple flow. A follow-up "refactor ReaderContainerView into composition" task is appropriate but out of WI-4c-b scope.
2. **Manual fallback used** — Codex MCP unavailable. Risk: bias from same-author audit. Mitigated by: (a) explicit edge-case grid (15 cases); (b) full symbol verification against post-change files; (c) actual spike-0 smoke test on real iOS Simulator proved the production path works end-to-end. Accepted per rule 47's "manual fallback is allowed only when the independent audit tool is genuinely unavailable" — `stream disconnected` is the genuine-unavailable case.
3. **TTSService.startSpeaking failure path** — if `AVAudioSession` cannot activate (e.g., simulator in silent mode), `startSpeaking` leaves state at `.idle` without throwing. The observer doesn't observe failure. Accepted for spike-0: the success path (audio activates) was empirically verified. The failure-detection surface is Feature #40's `ttsState` snapshot, not the spike.

## Summary verdict

**ship-as-is.**

Diff is small, well-scoped, fully tested at the parser layer, and end-to-end validated via spike-0 smoke test on iPhone 17 Pro Simulator. No security, concurrency, or correctness concerns introduced. The deferred items (dispatcher routing test, snapshot ttsState wiring) are downstream Feature #40 / #41 dependencies, not gaps in this WI.

Pre-existing concerns (ReaderContainerView file size) are noted but not introduced by this change.
