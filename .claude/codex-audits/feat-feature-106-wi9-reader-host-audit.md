---
branch: feat/feature-106-wi9-reader-host
threadId: 019edd-wi9-reader-2rounds
rounds: 2
final_verdict: ship-as-is
date: 2026-06-18
---

# Gate-4 audit — feature #106 WI-9 (Android EPUB reader host)

WI-9 hosts Readium's `EpubNavigatorFragment` (scroll mode) in `ReaderActivity`,
opening the stored EPUB via the WI-5 `BookOpener` and saving/restoring position
through the WI-6 `ReadiumLocatorBridge` + `ResumeResolver` → Room. The foundation
subset of `dev-docs/designs/.../vreader-reader.jsx` (open + render + resume; rich
controls are Phase 3). Resolves #1745. **Emulator-verified.**

Codex (gpt-5.4, high), 2 rounds.

## Round 1 — 2 High, 1 Medium (block-recommended)

| file | sev | issue | resolution |
|---|---|---|---|
| ReaderActivity | High | async open could resume after `onSaveInstanceState` → `commitNow` throws `IllegalStateException`. | Attach gated by `lifecycle.withStarted { … }` (runs only when ≥STARTED). **Round 2 hardened** (below). |
| ReaderActivity | High | the opened `Publication` was never closed → file-handle/WebView leak across sessions. | Stored in a field, `close()`d in `onDestroy()` (after `super.onDestroy()` tears the fragment down). |
| ReaderActivity | Medium | only the 1s-debounced save → the last movement in the debounce window was lost on back/home/rotation. | `onStop()` captures `currentLocator.value` and persists it on `container.appScope` (a process-lifetime `SupervisorJob` scope) so it completes through teardown. New test `backgrounding_flushesReadingPosition`. |

## Round 2 — leak + Medium confirmed resolved; the High re-flagged + definitively fixed

| file | sev | issue | resolution |
|---|---|---|---|
| ReaderActivity | High | `withStarted` alone doesn't close the window — the FragmentManager state could be saved while still STARTED, so `commitNow` could still throw. | Added an explicit `if (supportFragmentManager.isStateSaved) return@withStarted null` guard inside `withStarted`; on `null` the activity aborts + `finish()`es (the publication releases in `onDestroy`; the activity recreates fresh on return). This is the auditor's recommended abort-on-state-saved fix. |

Residual (not a defect): no instrumented test forces the precise
open-finishes-after-`onSaveInstanceState`-before-attach race — that timing race
can't be deterministically reproduced without fault injection. The `withStarted` +
`isStateSaved` guard makes the crash structurally impossible.

## Validation

- `scripts/run-android-tests.sh :app:testDebugUnitTest` → **SUCCEEDED** (48 unit tests).
- `scripts/run-android-verify.sh` (`:app:connectedDebugAndroidTest`) on
  **emulator-5554** → **SUCCEEDED**; 4 instrumented tests (BookOpener 2 + ReaderActivity
  2: `opensStoredEpub_rendersNavigator_andMarksOpened`,
  `backgrounding_flushesReadingPosition`), 0 failures.
- **Manual emulator render:** tapping a book in the Library opens `ReaderActivity`
  and Readium renders the EPUB ("Chapter 1 / Call me Ishmael.") with the back+title
  chrome (`dev-docs/verification/artifacts/feature-106-wi9-reader-render-20260618.png`).

## Verdict

**ship-as-is.** The Publication leak + debounce-flush Medium resolved with a test;
the `commitNow` High definitively closed with the `withStarted` + `isStateSaved`
guard (the recommended fix). The reader host is emulator-verified end-to-end. The
sole residual is a non-reproducible timing-race coverage gap, structurally
prevented. Zero open Critical/High/Medium that are reproducible.
