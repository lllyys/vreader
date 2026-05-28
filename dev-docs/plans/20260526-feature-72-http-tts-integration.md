# Feature #72 — HTTP cloud TTS provider integration (wire `HTTPTTSProvider` into the live read-aloud path)

Lifts Bug #270 / GH #1166 into a feature: the HTTP cloud-TTS provider is
configurable in Settings but never used at runtime (orphaned). Wiring it into
the live TTS pipeline is a product-integration capability that was never
implemented, so it follows the feature workflow (rule 47), not the bug workflow.

## Revision history

- **v1 (2026-05-26)** — Gate 1 draft.
- **v2 (2026-05-26)** — Gate-2 Codex audit round 1 (thread `019e6389`) returned
  5 High + 2 Medium. All addressed; see "Audit fixes applied (Gate 2 round 1)"
  at the end. Core corrections: real APIs (`HTTPTTSConfig.validate()` not
  `isValid`; `TTSProvider.synthesize` is `async throws`; `SpeechSynthesizing`
  has NO `delegateTarget` — added as WI-0 protocol change + generic delegate
  wiring in `TTSService`); UTF-16 offset map must be computed against the
  ORIGINAL utterance (chunkText trims whitespace → drift); fresh
  `HTTPTTSProvider` per utterance (`cancel()` is sticky); error handling folds
  into WI-3 via emitted `didCancel` (no existing error UI → no new UI, rule 51);
  audio-session stays owned by `TTSService`.

## ⚠ Read the "Audit fixes applied (Gate 2 round 1)" section at the end — it supersedes v1 details inline above where they conflict.

## Problem

`HTTPTTSProvider` (conforms to `TTSProvider`: `synthesize(text:voice:) async -> Data`,
`synthesizeChunked(...)`, `cancel()`) is fully implemented + Settings-configurable
(`HTTPTTSSettingsView` writes `HTTPTTSConfig` to UserDefaults + the API key to
Keychain) + covered by 43 unit tests — but it is **never constructed in
production**. The live read-aloud path (`ReaderContainerView`'s
`@State var ttsService = TTSService()`) drives a `SpeechSynthesizing` instance,
and `TTSService.defaultSynthesizer()` returns ONLY `SystemSpeechSynthesizer`
(or the DEBUG `XCUITestMockSpeechSynthesizer`). The two abstractions
(`SpeechSynthesizing ← TTSService`; `TTSProvider ← HTTPTTSProvider`) are
disconnected. Result: configuring an HTTP/cloud TTS endpoint does nothing —
read-aloud always uses the on-device `AVSpeechSynthesizer` voice.

This also corrects Feature #26's C6 ("HTTP cloud TTS end-to-end") gating: C6 is
**unimplemented**, not merely unverifiable.

## Goal

When a valid `HTTPTTSConfig` is configured, "Read aloud" plays the cloud
provider's synthesized audio instead of the on-device voice, integrated with the
existing TTS state machine (play / pause / resume / stop), control bar, and —
to the extent HTTP TTS allows — the reader's progress/auto-scroll.

## Chosen architecture — a `SpeechSynthesizing` adapter (fix-direction a)

Build `HTTPSpeechSynthesizer: SpeechSynthesizing` that wraps `HTTPTTSProvider` +
an `AVAudioPlayer`-backed chunk-playback queue, and have
`TTSService.defaultSynthesizer()` return it when `HTTPTTSConfig.validate() == .valid`
(v2 — `validate()`, not `isValid`).
Rejected: unifying `SpeechSynthesizing` / `TTSProvider` into one protocol — far
larger blast radius (every `SpeechSynthesizing` call site + the on-device path),
no benefit over the adapter for this goal.

### Why an adapter, and the central design constraint

`SpeechSynthesizing` delivers progress to `TTSService` through an
`AVSpeechSynthesizerDelegate` (`delegateTarget`) — notably
`speechSynthesizer(_:willSpeakRangeOfSpeechString:utterance:)`, which drives
sentence-highlight + auto-scroll, and `didFinish` / `didStart` / `didPause` /
`didContinue` / `didCancel`. **HTTP TTS returns audio bytes with no
word-boundary timing**, so the adapter cannot produce per-word `willSpeakRange`
events. The adapter therefore **emulates** the delegate callbacks:

- `synthesizeChunked` already splits text at sentence boundaries and yields
  `(chunkIndex, totalChunks, audioData)`. The adapter plays chunks sequentially
  via `AVAudioPlayer`; as each chunk's audio **starts**, it emits a
  `willSpeakRange` spanning **that chunk's character range** in the utterance
  (chunk-level, not word-level, highlight + auto-scroll). The adapter tracks the
  running UTF-16 offset of each chunk within the utterance string so the range
  is correct.
- `didStart` on first chunk; `didFinish` after the last chunk's audio completes;
  `didCancel` on stop. `pause`/`continue` map to `AVAudioPlayer.pause()` / `.play()`
  and emit `didPause` / `didContinue`.

This yields sentence-granularity highlight/scroll for cloud TTS — coarser than
the on-device per-word path, but functional and honest (documented in the row).

## Surface area (file-by-file)

### New files

| File | Responsibility |
|---|---|
| `vreader/Services/TTS/HTTPSpeechSynthesizer.swift` | **Behavioral.** `final class HTTPSpeechSynthesizer: SpeechSynthesizing`. Holds an injected `TTSProvider` (prod: `HTTPTTSProvider(config:)`), an `AVAudioPlayer`-backed sequential chunk queue, the current utterance + per-chunk UTF-16 offset map, and `weak var delegateTarget: AVSpeechSynthesizerDelegate?`. Implements `speak` (kick off chunked synth+playback), `pauseSpeaking`/`continueSpeaking`/`stopSpeaking`, `isSpeaking`/`isPaused`. Emits emulated delegate callbacks (chunk-range `willSpeakRange`, `didStart`/`didFinish`/`didPause`/`didContinue`/`didCancel`). `@MainActor` for delegate-callback + state parity with `SystemSpeechSynthesizer`. |
| `vreader/Services/TTS/HTTPTTSChunkPlayer.swift` (if `HTTPSpeechSynthesizer` exceeds ~250 lines) | **Behavioral.** Extracted `AVAudioPlayer` sequential-playback queue (enqueue audio `Data`, play next on `audioPlayerDidFinishPlaying`, pause/resume/stop), so the synthesizer file stays under the 300-line guideline. |

### Modified files

| File | Change | WI |
|---|---|---|
| `vreader/Services/TTS/TTSService.swift` | `defaultSynthesizer()` returns `HTTPSpeechSynthesizer(provider:)` when `HTTPTTSConfig` loads + `.isValid`, else `SystemSpeechSynthesizer()` (DEBUG mock path unchanged). Add a config-load helper (UserDefaults `httpTTSConfig` + Keychain key). | WI-3 |
| `vreader/Services/TTS/HTTPTTSConfig.swift` | (read-only consumer) confirm `isValid` + a `load()` accessor exist; add if missing. | WI-1 |
| `docs/architecture.md` | Note `HTTPSpeechSynthesizer` in the TTS/Services section + the SpeechSynthesizing-adapter pattern. | WI-final |

### Files OUT of scope

- `HTTPTTSSettingsView` / the Settings UI — already exists; no UI change (rule 51 N/A — pure integration).
- The on-device `SystemSpeechSynthesizer` path — untouched.
- `TTSProvider` / `HTTPTTSProvider` — consumed as-is; not modified.
- Word-level highlight for cloud TTS — explicitly out (no word timing from the provider); chunk-level only.

## Work-item sequencing

> **SUPERSEDED — see the v2 table in "Audit fixes applied (Gate 2 round 1)" at
> the end** (adds WI-0 for the protocol delegate change; folds failure handling
> into WI-3; shrinks WI-4 to verification + docs). The v1 table below is kept
> only for history.

## Test catalogue

| Test file | WI | Covers |
|---|---|---|
| `HTTPTTSConfigLoadTests` | WI-1 | `load()` returns nil when unset / invalid; valid round-trip; Keychain key read. |
| `HTTPTTSChunkPlayerTests` | WI-2 | enqueue→play-next ordering; pause/resume/stop; finish-callback advances queue; empty queue. Stubs the audio layer via a `SpeechAudioPlaying` protocol (no real AVAudioPlayer in unit tests). |
| `HTTPSpeechSynthesizerTests` | WI-3 | `speak` → chunked synth (stub `TTSProvider` returning canned audio) → emits `didStart`, per-chunk `willSpeakRange` with correct UTF-16 ranges, `didFinish`; pause/resume/stop map to player + emit `didPause`/`didContinue`/`didCancel`; `isSpeaking`/`isPaused` track state; `TTSService.defaultSynthesizer()` returns the HTTP synth when config valid, System otherwise. |
| `HTTPSpeechSynthesizerErrorTests` | WI-4 | synth throws → `didCancel` + error surfaced; chosen fallback behavior. |

## Risks + mitigations

| Risk | Mitigation |
|---|---|
| No word timing → highlight/scroll is chunk-granular, not per-word | Accept chunk-level (sentence) highlight; document the degradation in the feature row + a code comment. |
| Network failure mid-read-aloud | WI-4: emit `didCancel` + surface a user-visible error via the existing TTS error path; **proposed**: do NOT silently fall back to on-device mid-utterance (surprising); offer on-device as the configured default if HTTP is unconfigured/invalid. (Auditor: confirm.) |
| `AVAudioSession` category/activation conflicts with the on-device path | Configure `.playback` on first chunk; deactivate on stop/finish. Verify against the existing TTS audio-session handling. |
| Latency: first audio chunk arrives after a network round-trip | The control bar already shows a TTS-active state; consider a loading state. Scoped minimal for v1 (no new UI per rule 51 — reuse existing states). |
| `@MainActor` + async synth (provider is `async`/Sendable) | The synthesizer is `@MainActor`; provider calls hop via `Task`; callbacks marshalled to main. Mirror `SystemSpeechSynthesizer`'s isolation. |

## Backward compatibility

- Default behavior unchanged: with no `HTTPTTSConfig` (the common case),
  `defaultSynthesizer()` returns `SystemSpeechSynthesizer` exactly as today.
- DEBUG `XCUITestMockSpeechSynthesizer` path is preserved (selection checks the
  mock flag first, as today).
- No schema/persistence change; `HTTPTTSConfig` storage is unchanged.

## Acceptance criteria

1. With a valid `HTTPTTSConfig`, "Read aloud" plays cloud-synthesized audio (not the on-device voice).
2. The TTS state machine (idle→speaking→paused→speaking→idle) + control bar work with the HTTP synth.
3. Chunk-level highlight/auto-scroll advances as chunks play.
4. With no/invalid config, behavior is identical to today (on-device voice).
5. A synthesis/network failure surfaces a user-visible error and stops cleanly (no hang, no silent no-op).
6. Verified end-to-end against a real HTTP TTS endpoint (or a high-fidelity integration test through the real adapter boundaries with a stubbed network layer, per the close-gate exception — a live third-party TTS server is external infra).

## Gate 2 — Independent Plan Audit (COMPLETE — clean)

Codex MCP thread `019e6389`, **2 rounds**.
- **Round 1**: 5 High + 2 Medium (wrong API names; non-generic delegate wiring;
  drifting offset map; sticky `cancel()`; no error path; session ownership; WI-4
  too late). All resolved in "Audit fixes applied (Gate 2 round 1)" + the v2 WI
  table.
- **Round 2**: substantively clean — "implementation-ready in design terms";
  the only residual was a Low (stale v1 inline text), cleaned by the supersede
  banners + this section. **Zero open Critical/High/Medium.** Gate 2 passes.

---

## Audit fixes applied (Gate 2 round 1) — thread `019e6389`

Resolutions to the 5 High + 2 Medium. These supersede v1 inline details.

### H1 — wrong API names/shapes → corrected against real interfaces
- `HTTPTTSConfig` exposes `validate() -> ConfigValidationResult` (NOT `isValid`).
  The selection logic uses `config.validate()` and treats only a `.valid`
  result as "configured". (WI-1 wraps this in a small `isConfigured` convenience
  if it reads cleanly, built ON `validate()`, not a parallel check.)
- `TTSProvider.synthesize(text:voice:)` is `async throws`; `synthesizeChunked`'s
  `onChunk` is non-throwing. The adapter `try await`s synth + maps thrown
  errors to a clean stop (see H5).
- `SpeechSynthesizing` (SpeechSynthesizing.swift:22) has **no** `delegateTarget`
  requirement — only the concrete `SystemSpeechSynthesizer` declares it. See H2.

### H2 — delegate wiring is not generic → WI-0 protocol change
`TTSService` only wires the `AVSpeechSynthesizerDelegate` for the concrete
`SystemSpeechSynthesizer`/`XCUITestMockSpeechSynthesizer` types, so a new adapter
would receive no `willSpeakRange`/`didFinish`/`didCancel`. **New WI-0**: add
`var delegateTarget: AVSpeechSynthesizerDelegate? { get set }` to the
`SpeechSynthesizing` protocol (the concrete System synth already satisfies it),
and change `TTSService` to set `synthesizer.delegateTarget = self` generically
for ANY `SpeechSynthesizing` (not type-cased). This is a small, behavior-
preserving refactor that unblocks the adapter receiving callbacks.

### H3 — UTF-16 chunk-offset map drifts (chunkText trims whitespace)
`HTTPTTSProvider.chunkText` trims the whole text + each sentence + each split
chunk, so summing emitted-chunk lengths drifts from the original utterance.
**Fix**: do NOT derive offsets from chunk strings. WI-2/WI-3 compute each
chunk's UTF-16 range by **locating the chunk's first non-whitespace content in
the ORIGINAL utterance starting from the previous chunk's end** (a forward
`range(of:)` scan over the original `NSString`), preserving skipped whitespace.
The `willSpeakRange.location` emitted is that found start (TTSService uses only
`.location`, confirmed by the auditor). If a chunk can't be located (degenerate),
emit the previous offset (no scroll jump) rather than a wrong one.

### H4 — HTTPTTSProvider.cancel() is sticky (never reset)
`_isCancelled` is set once and gates `synthesizeChunked` forever. **Fix**: the
adapter constructs a **fresh `HTTPTTSProvider(config:)` per `speak()`** (cheap;
the provider is a thin URLSession wrapper) so a prior `stopSpeaking()` →
`cancel()` never bricks the next utterance.

### H5 — no existing TTS error path → emit didCancel (no new UI; rule 51)
`TTSService` exposes only `state` + `currentOffsetUTF16`; the control bar reacts
to play/pause/stop only — there is **no** error-presentation surface, and adding
one is new UI (rule 51 — would need a design). **Fix folds into WI-3, not WI-4**:
on synth/network failure the adapter emits the delegate's **`didCancel`**, which
`TTSService` already handles → returns the state machine to `.idle` (clean stop,
NOT stranded in `.speaking`). The error is logged via `OSLog`. A *user-visible*
error toast/message is explicitly deferred to a designed follow-up (`needs-design`)
— out of scope here to avoid self-designed UI. Acceptance criterion 5 is
restated as: "a synthesis/network failure stops cleanly (returns to idle, logged)
— no hang, no silent stuck-in-speaking."

### M1 — audio-session ownership stays in TTSService
`TTSService.startSpeaking()`/`stop()` already activate/deactivate
`AVAudioSession` (`.playback`). The adapter must **not** manage the session —
it plays its `AVAudioPlayer` chunks within the session `TTSService` already
activated before calling `speak`. (Confirmed `.playback` suits both
`AVSpeechSynthesizer` and `AVAudioPlayer`.) No duplicate/split ownership.

### M2 — fold failure handling into WI-3; WI-4 = verification/docs only

### Revised work-item sequencing (v2)

| WI | Title | Tier | Est. PR |
|---|---|---|---|
| **WI-0** | `SpeechSynthesizing.delegateTarget` protocol requirement + generic delegate wiring in `TTSService` (no type-casing); System/Mock paths unchanged | Foundational (refactor) | Small |
| **WI-1** | `HTTPTTSConfig` load + `validate()`-based `isConfigured` accessor (UserDefaults `httpTTSConfig` + Keychain key) | Foundational, pure | Small |
| **WI-2** | `HTTPTTSChunkPlayer` — `AVAudioPlayer` sequential queue behind a `SpeechAudioPlaying` test seam (enqueue/play-next/pause/resume/stop); does NOT touch AVAudioSession | Behavioral | Medium |
| **WI-3** | `HTTPSpeechSynthesizer: SpeechSynthesizing` — fresh-provider-per-utterance chunked synth + playback + emulated callbacks (original-utterance chunk-range `willSpeakRange`, `didFinish`, **`didCancel` on failure**); `TTSService.defaultSynthesizer()` returns it when `config.validate() == .valid` | Behavioral | Medium |
| **WI-4** | End-to-end verification (real endpoint or high-fidelity integration test through the real adapter with a stubbed network layer) + `architecture.md` doc-sync + full acceptance pass | Behavioral (final) | Small–Medium |

### Confirmations from the audit (no change needed)
- Chunk-level (sentence) `willSpeakRange` is sufficient: `TTSService` uses only
  `characterRange.location` (ignores `.length`) → `currentOffsetUTF16` →
  `TTSHighlightCoordinator` maps to the NLTokenizer sentence. Coarse offsets are
  tolerated; only offset *correctness* matters (→ H3).
- `didStart`/`didPause`/`didContinue` are NOT consumed by `TTSService` (it drives
  start/pause/resume directly); the adapter need only emit `willSpeakRange`,
  `didFinish`, `didCancel`.
- `AVAudioPlayer` sequential playback (play next on
  `audioPlayerDidFinishPlaying`) is the right model (whole `Data` chunks, simple
  transport) — not `AVQueuePlayer`/`AVAudioEngine`.
- Fallback policy: surface-error-and-stop (here: clean `didCancel` stop) is
  correct; fall back to on-device ONLY when config is absent/invalid BEFORE
  starting, never mid-utterance.
