# Feature #121 — Android TTS read-aloud

**Status:** Gate 1 (plan), v2 (Gate-2 audit round 1 applied). Part of the #110 Android Phase-3
capability-parity driver. Implements the TTS read-aloud design
(`dev-docs/designs/vreader-fidelity-v1/project/vreader-tts.jsx`, needs-design #1797 closed) on
Android's on-device `android.speech.tts.TextToSpeech`.

## Problem

iOS reads books aloud (#26/#72, `AVSpeechSynthesizer`) with a control bar, spoken-sentence highlight,
and auto-scroll follow. Android has the runtime (`TextToSpeech`) but no read-aloud — no engine wrapper,
no control bar, no highlight. This adds read-aloud to the Android reader, starting with the **TXT
reader** (simplest text source, exact char offsets), behind a format-agnostic engine so EPUB/PDF/MD
wire in later.

## Surface area (all new, under `android/app/.../tts/` + a TxtReaderActivity integration)

- **`tts/TtsModels.kt`** (WI-1, pure) — `TtsPhase { idle, speaking, paused, error }`;
  `TtsErrorKind { initFailed, noVoiceData, languageNotSupported, speakFailed }`;
  `TtsUtterance(generation, index, text)` — **`generation` is a monotonic token stamped at every
  start/pause/stop/next**; `TtsProgress` sealed, each case carries the `generation`
  (`Started(generation, index)`, `Range(generation, index, charStart, charEnd)`, `Done(generation, index)`,
  `Failed(generation, index?, kind)`). The Android utterance id encodes `"$generation:$index"`, so a
  callback from a flushed (stale-generation) queue is unambiguously discarded by the VM regardless of
  index reuse (e.g. resume from the same sentence). `TtsEngineOption(id, label)`;
  `TtsVoiceOption(name, locale, label, networkRequired, notInstalled)`; `TtsInitResult { ok, failed }`.
- **`tts/TtsChunker.kt`** (WI-1, pure) — split a decoded book `String` into speakable **sentences**,
  each with `charStart`/`charEnd` (UTF-16 against the raw text → maps back to a `TxtDocument` chunk).
  Boundaries: `.?!` + closing quotes/brackets + whitespace; CJK `。？！…`; an abbreviation guard
  (don't split "Mr."/"Dr."/"e.g."); collapse blank runs; **hard-cap each utterance at
  `maxUtteranceChars` (caller passes `TextToSpeech.getMaxSpeechInputLength()`)**, never mid-surrogate.
  Invariant: `text.substring(s.charStart, s.charEnd)` reconstructs the sentence's source span.
- **`tts/TtsEngine.kt`** (WI-1, pure interface — the test seam): `suspend fun awaitInit(): TtsInitResult`;
  `fun speak(utterance: TtsUtterance): Boolean` (ONE utterance, `QUEUE_ADD`, returns the
  `SUCCESS`/`ERROR` mapped Boolean); `fun stop()`; `fun setRate(rate: Float): Boolean`
  (caller pre-clamps); `fun setVoice(name: String?): Boolean`;
  `val progress: Flow<TtsProgress>`; `fun engines(): List<TtsEngineOption>`;
  `fun voices(locale: Locale?): List<TtsVoiceOption>`; `fun isLanguageAvailable(locale: Locale): Int`
  (raw `TextToSpeech` code, mapped by the VM); `fun shutdown()`. **Engine switching is NOT a setter** —
  `setEngineByPackageName` is deprecated; switching engines = shutdown + recreate the `AndroidTtsEngine`
  with the new package (`TextToSpeech(appContext, listener, enginePackageName)`) + `awaitInit()`, owned
  by an `AndroidTtsEngineFactory(appContext).create(enginePackage?)` the VM calls.
- **`tts/AndroidTtsEngine.kt`** (WI-2, platform) — the `TextToSpeech` wrapper. Built with the
  **application context** (never an Activity — no leak if the owner outlives the Activity). Init via the
  `OnInitListener` bridged to `awaitInit()` (a `suspendCancellableCoroutine`, resumed once). `speak`
  enqueues ONE utterance (`QUEUE_ADD`, a per-utterance id) and returns the mapped status; an
  `UtteranceProgressListener` forwards onStart/onRangeStart/onDone/onError into a thread-safe
  `MutableSharedFlow` (extraBufferCapacity, `tryEmit`) exposed as `progress` — **callbacks are not
  guaranteed on main, so the flow is the thread boundary; the VM collects on main**. `voices()` reads
  `tts.voices` mapping `Voice.isNetworkConnectionRequired`/`features` → `networkRequired`/`notInstalled`;
  `engines()` from `tts.engines`; `isLanguageAvailable` returns the raw code. The instance is touched
  only after a successful init. `shutdown()` calls `tts.stop()` + `tts.shutdown()`. An
  `AndroidTtsEngineFactory(appContext)` constructs the engine (optionally for a specific engine package)
  so the VM can switch engines by recreate-and-await. **Manifest (WI-2): add the Android-11 package
  visibility `<queries><intent><action android:name="android.intent.action.TTS_SERVICE"/></intent></queries>`**
  (== `TextToSpeech.Engine.INTENT_ACTION_TTS_SERVICE`) so `tts.engines`/init can see installed TTS engines
  on API 30+.
- **`tts/TtsViewModel.kt`** (WI-3, `ViewModel`) — owns the engine (constructed with the **application
  context**; `shutdown()` in `onCleared`) and a `StateFlow<TtsUiState>`. Transitions:
  - **current-sentence advance is driven by `TtsProgress.Started(index)`** (canonical — fires on every
    engine); `Range` only refines the highlight span WITHIN the current sentence; `Done` of the last
    queued utterance triggers a refill or `idle`.
  - **pause/resume**: Android `TextToSpeech` has no true pause — `pause()` = `engine.stop()` + retain
    the current sentence index as the resume anchor + phase `paused`; `play()` re-speaks from the
    anchor. **A generation token bumps on every start/pause/stop/next/prev** so a stale callback from a
    flushed queue is discarded.
  - **queue window**: enqueue the current + next `K` sentences only (not the whole book); on `Done`,
    enqueue the next one — bounded memory, mirrors the iOS chunk-ahead.
  - **rate**: `setRate` clamps to `0.5f..2.0f` and rejects non-finite (NaN/∞) at the VM AND the
    persistence boundary, then asserts the engine returned success.
  - **error mapping**: init failure → `initFailed`; `isLanguageAvailable` ∈
    {`LANG_MISSING_DATA`,`LANG_NOT_SUPPORTED`} → `noVoiceData`/`languageNotSupported`; a `speak`/`setVoice`
    ERROR → `speakFailed`; an `onError` listener event → `speakFailed`. "No voice data" is surfaced
    ONLY when actually proven by a language check, never assumed.
  - **locale source**: Android `Book` has NO language field (confirmed — `LibraryRepository.Book` is
    fingerprint/title/format/sha/bytes/paths/timestamps). v1 uses **`Locale.getDefault()`** as the read
    locale (+ a cheap best-effort script sniff for CJK to prefer a CJK voice when the default is Latin);
    a persisted per-book language is a future schema change, explicitly out of scope.
  - **network voices**: default to an **embedded** (non-network) voice; network-required voices are
    listed + labeled in the sheet but never auto-selected.
  - **system-settings event**: `installVoiceData()`/`openSystemTts()` emit a one-shot
    `SharedFlow<TtsIntent>` the Activity launches. Voice-data install uses the public
    `Engine.ACTION_INSTALL_TTS_DATA`. **There is NO public `Settings.ACTION_TTS_SETTINGS`** — the
    "System TTS" CTA fires the de-facto action string `"com.android.settings.TTS_SETTINGS"` guarded by
    `resolveActivity` (`PackageManager`), falling back to `Settings.ACTION_ACCESSIBILITY_SETTINGS` then
    `ACTION_SETTINGS`, all wrapped in a try/catch so a device without it never crashes. The Activity
    (not the VM) does the resolve so the VM stays platform-free.
- **`tts/TtsUiState.kt`** (WI-3) — `TtsUiState(phase, sentenceIndex, charStart, charEnd, rate, rateLabel,
  voiceLabel, engineLabel, error, progressFraction)` + `TtsVoiceListState`/`TtsSpeedState`.
- **UI (Compose, WI-4, per the design):**
  - `tts/TtsControlBar.kt` — the glassy docked transport (`TtsBar`): progress line, status row, speed
    chip, prev/play-pause/next, close, voice/engine chip; plus the **error** layout (no-voice-data →
    "Install voice data" [→ intent] + "System TTS"). **Uses the reader's `VReaderColors`/`VReaderFonts`**
    (the in-reader surface; the Android app is light-only today — paper rendering, dark deferred with the
    reader's future theme system).
  - `tts/TtsVoiceSheet.kt` + `tts/TtsSpeedSheet.kt` — engine/voice list + rate slider/pills; **reuse the
    backup `AppSheet`/`SettingsCard`/`GroupHeader`/`GroupFooter` + `BackupTokens`** (the settings-sheet
    vocabulary, which already has light+dark).
- **`reader/TxtReaderActivity.kt` integration (WI-5)** — adds the **designed reader bottom toolbar** (per
  `vreader-tts.jsx` `TtsEntry`: Contents / Read-aloud(Volume) / Aa / AI — the Android TxtReader has only
  top chrome today, so this builds the depicted bottom toolbar) with the Read-aloud entry → builds
  sentences from the already-decoded `TxtDecoder` text via `TtsChunker(maxUtteranceChars = getMaxSpeechInputLength())`
  → starts the VM → docks `TtsControlBar` → **highlights the spoken sentence's char-range in the TXT
  `LazyColumn`** (`charStart` → `TxtDocument.chunkForOffset` → scroll the chunk into view + wash the
  span) → auto-scrolls to keep it visible.

### Files OUT of scope

- **MD / EPUB / PDF / Foliate TTS** — the engine + bar + VM are format-agnostic, but only the **TXT**
  reader is wired. The spoken-sentence **span highlight is TXT-only**: `MarkdownRenderer` renders a
  styled `AnnotatedString` that DROPS markdown markers (headings/bullets/emphasis/code/escapes), so raw
  char offsets don't map to rendered spans — MD/EPUB read-aloud + their offset maps are a documented
  follow-on under #110.
- **In-app voice-data download** — Android voice data installs via the **system** TTS settings /
  `ACTION_INSTALL_TTS_DATA` intent, not the app. The design's "Install voice data"/"Download" CTAs fire
  the system intent. No in-app downloader.
- **Background / lock-screen `MediaSession` playback** — the design is explicit ("not a system
  media-notification surrogate"). **Process death stops playback** (no MediaSession); a future capability.
- **Persisted per-book reading language** — needs a `Book` schema column; v1 uses the system locale.

## Prior art / project precedent / rejected alternatives

- **iOS**: `TTSService.swift` (speak/queue/state), `TTSProviderProtocol`+`SpeechSynthesizing` (the engine
  seam our `TtsEngine` mirrors), `TTSTextSource.swift` (sentence segmentation = our `TtsChunker`),
  `Views/Reader/TTSControlBar.swift`, `TTSHighlightCoordinator.swift`. Android mirrors these.
- **Android runtime**: `android.speech.tts.TextToSpeech` — `onRangeStart` + `Voice` are API ≥ 26
  (== minSdk 26). On-device engines (Google/Samsung) need no credentials; some VOICES are network-backed
  (`Voice.isNetworkConnectionRequired`) — handled, not assumed-away.
- **Reuse**: `TxtDocument.chunkForOffset`/`TxtDecoder.decode` (exist), the backup form primitives +
  `BackupTokens` for the sheets, `VReaderColors`/`VReaderFonts` for the in-reader bar.
- **Rejected — EPUB-first / in-app voice download / batch-queue-whole-book / `onRangeStart`-driven
  sentence advance** — see the audit-driven fixes above.

## Work-item sequencing (5 WIs — WI-1 split per audit)

| WI | Scope | Tier | PR size |
| --- | --- | --- | --- |
| WI-1 | `TtsModels` + `TtsChunker` + `TtsEngine` interface — PURE (no Android runtime). JVM tests. | foundational | medium |
| WI-2 | `AndroidTtsEngine` — the `TextToSpeech` wrapper (app-context, suspend init, callbackFlow progress, enumeration, error/voice mapping, shutdown). Instrumented smoke. | behavioral (platform) | medium |
| WI-3 | `TtsViewModel` + `TtsUiState` — the state machine (Started-driven advance, pause=stop+anchor+resume, generation tokens, bounded queue, rate clamp, locale source, network-voice policy, intents). Robolectric + fake engine. | behavioral | medium |
| WI-4 | `TtsControlBar` (VReaderColors) + `TtsVoiceSheet` + `TtsSpeedSheet` (BackupTokens), per the design, all states incl. error. Instrumented Compose. | behavioral | medium |
| WI-5 | `TxtReaderActivity` integration: the designed bottom toolbar + Read-aloud entry → sentences → dock bar → TXT spoken-sentence highlight + auto-scroll. Device/connected verification → VERIFIED. | behavioral (final) | medium |

## Test catalogue

- `TtsChunkerTest` (JVM): `.?!`/closing-quote/CJK boundaries, abbreviation guard, blank-collapse,
  `maxUtteranceChars` hard-cap + surrogate safety, empty/whitespace, the
  `substring(charStart,charEnd)==sentence` round-trip invariant.
- `AndroidTtsEngineTest` (instrumented smoke): `awaitInit()` returns ok-or-typed-error on the emulator,
  `engines()`/`voices()` enumerate, `isLanguageAvailable` callable — no audible-output assertion.
- `TtsViewModelTest` (Robolectric + fake engine): start→speaking, `Started` advances the index,
  pause→stop+anchor+paused, play→re-speak-from-anchor, next/prev clamp, last `Done`→idle, `setRate`
  clamp+non-finite-reject, `selectVoice`/`selectEngine`, error mapping (init/no-voice-data/speak-fail),
  generation-token discards stale progress after stop/pause, network-voice-not-auto-selected, the
  one-shot intent event.
- Compose: `TtsControlBarTest` (idle/speaking/paused/error + transport callbacks + install/system CTAs),
  `TtsVoiceSheetTest`, `TtsSpeedSheetTest`.
- `TxtTtsConnectedTest` (androidTest): open a real TXT book → Read-aloud → the VM reaches `speaking`
  with an advancing sentence index OR the typed `noVoiceData` error (both valid passes on an
  engine/voice-less emulator); the highlight char-range maps to a valid `TxtDocument` chunk.

## Risks + mitigations

- **Emulator lacks TTS voice data** → init ok but no audio / `LANG_MISSING_DATA`. The **typed error
  state is a first-class designed outcome** — verification asserts EITHER `speaking`+advancing-index OR
  the `noVoiceData` error in the bar. Audible output never asserted (unobservable headless, as on iOS).
- **`TextToSpeech` main-thread + init race** → app-context construction, suspend-init bridged once,
  instance touched only post-init, `shutdown()` in `onCleared`/`onDestroy`.
- **Progress-callback threading** → callbacks → `MutableSharedFlow.tryEmit` → VM collects on main; tests
  cover stale events after stop.
- **`onRangeStart` engine variance** → sentence advance keys on `Started` (always fires); `Range` only
  refines the span, so the highlight is robust even if `Range` never fires.
- **Long books** → bounded queue window (current + K), refill on `Done`.
- **Rotation / process death** → engine owned by the AndroidX `ViewModel` (survives rotation); process
  death stops playback (documented; MediaSession is the future fix). App-context = no Activity leak.

## Backward compat

Purely additive: a new `tts/` package, a new designed reader bottom toolbar in the TXT reader, and a
small `TtsPreferences` (DataStore — rate/voice/engine, defaulted, no migration). No schema change, no
effect on existing readers/formats.

## Audit history (Gate 2)

- **Round 1** (Codex, plan v1 → v2): 6 High + 6 Medium. Fixed: WI-1 split into pure (WI-1) + platform
  AndroidTtsEngine (WI-2); sentence advance keyed on `Started` not `onRangeStart`; engine `speak` one
  utterance + chunker caps at `getMaxSpeechInputLength`; pause = stop+anchor+resume w/ generation token;
  app-context + ViewModel-owned engine, process-death documented; `MutableSharedFlow` progress threading;
  richer error mapping (no-voice-data only when proven); network voices labeled + never auto-selected;
  locale = `Locale.getDefault()` (Book has no language field); bar uses `VReaderColors`, sheets use
  `BackupTokens` (no nonexistent THEMES); highlight scoped TXT-only (MD offsets don't map); WI-5 builds
  the designed bottom toolbar; rate clamp 0.5–2.0 + non-finite reject.
- **Round 2** (Codex, plan v2 → v3): 2 High + 2 Medium. Fixed: `TtsProgress`/`TtsUtterance` carry a
  `generation` token encoded into the Android utterance id (stale-callback discard survives resume from
  the same sentence); engine switching = shutdown+recreate via `AndroidTtsEngineFactory`, NOT the
  deprecated `setEngineByPackageName`; WI-2 adds the Android-11 `<queries>` TTS_SERVICE package
  visibility; the "System TTS" CTA uses a `resolveActivity`-guarded de-facto action with public
  fallbacks (no nonexistent `Settings.ACTION_TTS_SETTINGS`). Codex confirmed the remaining assumed APIs
  (`getMaxSpeechInputLength`, `ACTION_INSTALL_TTS_DATA`, `Voice.isNetworkConnectionRequired`,
  `tts.voices`/`tts.engines`, `suspendCancellableCoroutine`) are real and the 5-WI split is correct.
