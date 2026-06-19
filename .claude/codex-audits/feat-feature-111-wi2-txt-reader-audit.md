---
branch: feat/feature-111-wi2-txt-reader
threadId: 019edf-wi2-txt-1round
rounds: 1
final_verdict: ship-as-is
date: 2026-06-19
---

# Gate-4 audit — feature #111 WI-2 (Android TXT reader render + format routing)

WI-2 renders a decoded `.txt` in a Compose `LazyColumn` over the WI-1 `TxtDocument`
chunk ranges, with the shared back+title chrome, and routes the Library tap by typed
format (`txt` → `TxtReaderActivity`, `epub` → `ReaderActivity`). Emulator-verified
incl. the real 14MB UTF-16LE CJK book.

Codex (gpt-5.4, high), 1 round, follow-up-recommended → fixed to ship-as-is.

## Findings (3 Medium, 1 Low — all fixed)

| file | sev | issue | resolution |
|---|---|---|---|
| MainActivity.kt | Medium | `when` sent every non-`txt` book to the EPUB-only `ReaderActivity` — pdf/md/azw3 (which `BookImporter` accepts) would open into the wrong host + fail. | Exhaustive `when` over `BookFormat`: `epub`→`ReaderActivity`, `txt`→`TxtReaderActivity`, `pdf`/`md`/`azw3`→a "not available yet" Toast (never mis-open). |
| TxtReaderActivity.kt | Medium | the decode/build path had no failure boundary — an I/O error from `TxtDecoder.decode(File(path))` would escape the `produceState` coroutine and crash. | Wrapped the loader in `runCatching { … }.getOrDefault(TxtUiState.Failed)`. |
| TxtReaderActivity.kt | Medium | `(0 until document.chunkCount).toList()` eagerly boxed every chunk index (100k+ on a newline-dense 14MB file). | Switched to the count-based `items(count = document.chunkCount, key = { it })` — indices on demand, no boxed list. |
| TxtReaderActivity.kt | Low | `finish()` called directly in the composition branch (a side effect in render, repeatable across recompositions). | Moved the Failed-state close into `LaunchedEffect(Unit) { finish() }`. |

## Validation

- `scripts/run-android-tests.sh :app:testDebugUnitTest` → SUCCEEDED (48 unit tests).
- `scripts/run-android-verify.sh` (`:app:connectedDebugAndroidTest`) on emulator-5554
  → SUCCEEDED; 5 instrumented tests incl. `TxtReaderActivityTest.opensStoredTxt_
  rendersDecodedText` (Compose UI test asserts the decoded text renders), 0 failures.
- **Manual real-book render:** the 14MB UTF-16LE CJK novel `黑暗血时代` renders legibly
  with the chrome — encoding detection + CJK + large-file + txt routing all work
  (`dev-docs/verification/artifacts/feature-111-wi2-txt-realbook-20260619.png`).

## Verdict

**ship-as-is.** All 4 findings fixed + re-verified on the emulator (the render test
still passes; routing now exhaustive; decode failure-safe; memory-lean).
