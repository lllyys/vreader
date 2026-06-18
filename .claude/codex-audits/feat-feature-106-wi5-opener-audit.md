---
branch: feat/feature-106-wi5-opener
threadId: 019edb-wi5-opener-2rounds
rounds: 2
final_verdict: ship-as-is
date: 2026-06-18
---

# Gate-4 audit — feature #106 WI-5 (Readium EPUB publication opener)

WI-5 ships the UI-free EPUB **open/parse** path (the visible reader host that
RENDERS the publication is design-blocked #1745): `BookOpener` drives the Readium
`AssetRetriever → PublicationOpener` flow (lifted from the verified Spike-B
harness) → a `Publication` + `readMetadata` (title, reading-order size). Readium
3.3.0 `readium-shared` + `readium-streamer` (no navigator — opening only).
**Verified on the emulator** (instrumented test), not just compiled.

Codex (gpt-5.4, high), 2 rounds.

## Round 1 — 3 Medium, 2 Low (follow-up-recommended)

| file | sev | issue | resolution |
|---|---|---|---|
| BookOpener.kt | Medium | If `retrieve()` succeeded but `open()` failed, the intermediate Readium `Asset` (an open file handle) leaked. | `openInternal` holds the Asset behind a `handedOff` flag in try/finally; `asset.close()` on every exceptional exit after retrieval; ownership transfers to the `Publication` only on success. |
| BookOpener.kt | Medium | `require(file.exists())` threw raw `IllegalArgumentException`, breaking the typed-error boundary. | `if (!file.exists()) throw BookOpenException(...)`. Instrumented test `open_missingFile_throwsTyped`. |
| BookOpener.kt | Medium | Blocking disk/ZIP/XML parse ran on the caller's coroutine context (UI ANR risk). | Injected `ioDispatcher: CoroutineDispatcher = Dispatchers.IO`; `open`/`readMetadata` wrap `openInternal` in `withContext(ioDispatcher)` (mirrors `BookImporter`). |
| build.gradle.kts | Low | `androidx.appcompat` was unused (Readium 3.3.0 shared/streamer don't declare it). | Removed — the unit build AND the emulator instrumented test still pass, confirming it's not needed. |
| build.gradle.kts | Low | Duplicate experimental opt-in (module-wide flag + file `@OptIn`). | Removed the module-wide `freeCompilerArgs` opt-in; kept the file-level `@OptIn(ExperimentalReadiumApi::class)` on `BookOpener` (the only user). |

## Round 2 — all resolved, no new findings (ship-as-is)

Auditor confirmed each fix. Residual: no automated test forces the
retrieve-succeeds/open-fails path (would need a Readium fault-injection harness) —
a coverage gap, not a correctness finding. The path is structurally correct
(`handedOff` flag) and the happy + missing-file paths are emulator-verified.

## Validation

- `scripts/run-android-tests.sh :app:testDebugUnitTest` → **SUCCEEDED** (40 JVM
  tests; Readium deps compile, existing tests unaffected).
- `scripts/run-android-verify.sh` (`:app:connectedDebugAndroidTest`) on
  **emulator-5554 (vreader-test AVD)** → **SUCCEEDED**; `BookOpenerTest` 2 tests
  (`open_minimalEpub_readsMetadata` — opens the bundled minimal EPUB, asserts
  title="Minimal Test Book" + readingOrderCount≥1; `open_missingFile_throwsTyped`),
  0 failures. **Real Gate-5 emulator verification.**
- `contracts/conformance/run.sh kotlin` unaffected (no `:identity` change).

## Verdict

**ship-as-is.** All round-1 findings (3 Medium + 2 Low) resolved; the open path is
emulator-verified end-to-end (Readium genuinely parses a stored EPUB). Zero open
Critical/High/Medium after 2 rounds.
