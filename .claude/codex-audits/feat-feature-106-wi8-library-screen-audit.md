---
branch: feat/feature-106-wi8-library-screen
threadId: 019edc-wi8-library-2rounds
rounds: 2
final_verdict: ship-as-is
date: 2026-06-18
---

# Gate-4 audit — feature #106 WI-8 (Android Library screen)

WI-8 implements the COMMITTED design `dev-docs/designs/vreader-fidelity-v1/project/
vreader-library.jsx` in Compose (rule-51-compliant — the user designated the iOS
bundle as the Android design source, #1744 unblocked). Theme tokens + `LibraryViewModel`
(Room-backed `StateFlow` + SAF import via the WI-4 `BookImporter`) + `LibraryScreen`
(nav bar / serif title / grid+list / fallback covers / empty state) + `VReaderApp`
manual-DI container + `MainActivity` SAF `OpenDocument` wiring.

Codex (gpt-5.4, high), 2 rounds. **Emulator-verified** (not just compiled).

## Round 1 — 5 Medium, 1 Low (follow-up-recommended)

| file | sev | issue | resolution |
|---|---|---|---|
| LibraryViewModel | Medium | `resolver.query()`/`openInputStream()` ran on the main-thread `viewModelScope` (SAF stall). | Injected `ioDispatcher`; resolve in `withContext(ioDispatcher)`. |
| LibraryViewModel | Medium | broad `catch (Exception)` swallowed `CancellationException`. | `catch (e: CancellationException) { throw e }` before the generic catch. |
| LibraryViewModel / MainActivity | Medium | non-replaying `SharedFlow` + `LaunchedEffect` dropped the import-error toast across a config-change collector gap. | `Channel<LibraryEvent>(BUFFERED)` + `receiveAsFlow()`; `trySend`. |
| MainActivity | Medium | picker advertised only `application/epub+zip` (EPUBs typed `octet-stream`/generic became unimportable). | Broadened to `epub+zip`/`octet-stream`/`*/*`; `BookImporter` rejects non-EPUB by extension. |
| LibraryScreen | Medium | non-functional search + settings pills (dead controls). | Removed both; kept the functional view-toggle + import. |
| LibraryScreen | Low | grid/list mode in plain `remember` (lost on rotation). | `rememberSaveable` boolean. |

## Round 2 — all 6 resolved; 1 new Medium (fixed)

| file | sev | issue | resolution |
|---|---|---|---|
| LibraryViewModel | Medium | `openInputStream()` (now inside `withContext`) can throw BEFORE the try/catch → escapes the launch instead of surfacing `ImportFailed`. | Wrapped the WHOLE resolve+import body in one try/catch (rethrow `CancellationException`, convert real failures to `ImportFailed`). New test `import_unopenableUri_emitsFailure`. |

The round-2 finding is a try/catch-scope widening directly covered by the new test
(an unregistered URI → `openInputStream` null → `ImportFailed`), so it ships clean
rather than as an open follow-up.

## Validation

- `scripts/run-android-tests.sh :app:testDebugUnitTest` → **SUCCEEDED**;
  `LibraryViewModelTest` 4 tests (uiState mapping, import-unsupported-failure,
  import-unopenable-failure, import-epub-adds-to-library), full `:app` suite 48,
  0 failures.
- **Gate-5 emulator verification (emulator-5554, vreader-test AVD):** the empty
  state, the populated **grid** (2 books incl. a CJK title, fallback covers,
  "2 books · 1 reading"), and the **list** view all render faithful to
  `vreader-library.jsx`; the grid↔list toggle works. Evidence:
  `dev-docs/verification/artifacts/feature-106-wi8-library-{empty,grid,list}-20260618.png`.

## Verdict

**ship-as-is.** All round-1 findings (5 Medium + 1 Low) + the round-2 Medium
resolved with tests; the Library screen is emulator-verified rendering the committed
design. Zero open Critical/High/Medium after 2 rounds.
