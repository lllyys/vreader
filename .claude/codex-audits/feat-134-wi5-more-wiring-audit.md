---
branch: feat/134-wi5-more-wiring
threadId: 019f513a-d1db-7973-8dfa-2d0bb52ec9ec
rounds: 2
final_verdict: ship-as-is
date: 2026-07-11
---

# Gate-4 audit — feature #134 WI-5 (More menu + Book Details + Share host wiring)

Independent Codex audit (gpt-5.6-sol, read-only sandbox) of the WI-5 integrator diff:
`ReaderSheet.Details` route + the WI-3 `MorePopup` / WI-4 `BookDetailsSheet` wiring across
all four reader hosts. Reports in `.reports/wi5-audit.txt` (round 1) and
`.reports/wi5-audit-r2.txt` (round 2).

## Round 1 — session 019f513a-d1db-7973-8dfa-2d0bb52ec9ec

**Verdict: block-recommended** — one P1 finding, everything else consistent.

- **[P1] EPUB null-Details route blocked reader touch-through.** `EpubReaderSheets`
  laid its full-screen `epub-sheet-dismiss-overlay` for ANY non-`None` route BEFORE the
  `when` checked `bookDetails`. A `ReaderSheet.Details` route with a null model rendered
  no `BookDetailsSheet` yet left the invisible overlay intercepting Readium
  scroll/selection/link input — a dead route contradicting the claimed touch-through
  no-op. Fix: normalize `(sheet is Details && bookDetails == null)` back to `None` and
  return BEFORE the overlay is created; add an EPUB-specific regression test.

Confirmed consistent in round 1:
- Every `when` over `ReaderSheet` (state `token()`/`sheetFromToken()`, `ReaderChromeScaffold`,
  `EpubReaderChrome`) has a `Details` branch (Kotlin exhaustive-when compiles).
- `ReaderChromeStateSaver` round-trips the new `details` token (JVM test).
- The More menu supplies exactly Details + Share — no dead TTS/Auto-turn/Bilingual/Export.
- copy-fingerprint copies `fingerprintFull` to the OS clipboard, no custom toast (rule 51).
- All four hosts build `BookDetailsUiModel` via `BookDetailsMapper` + the collection-name flow.
- Share delegates to the hardened WI-2 `shareBook`/`BookShareIntent` (graceful no-receiver).
- No WI-1..WI-4 merged file is modified — WI-5 only consumes those APIs.

## Round 2 — session 019f513d-00f0-7de2-a074-e7f0715539fe

Re-audit of the P1 fix (`EpubReaderChrome.kt` guard + the new `EpubReaderChromeTest`).

**Verdict: ship-as-is** — no new critical/high issues. The guard normalizes a null-model
Details route to `None` and returns before the dismiss overlay is created (touch-through
preserved); `EpubReaderChromeTest` asserts (a) null-model Details → no
`epub-sheet-dismiss-overlay`, no `book-details-sheet-content`, state normalized to `None`;
(b) model present → the Details sheet renders.

## Test gate

`RUN-ANDROID-TESTS RESULT: SUCCEEDED` — `:app:compileDebugKotlin` +
`:app:compileDebugAndroidTestKotlin` + `:app:testDebugUnitTest` all green.
New JVM signal: `ReaderChromeStateSaverTest` 12/12 (incl. the two Details round-trip cases),
`ReaderMoreRowsTest` 5/5. Live Compose/connected chrome tests ride WI-6 acceptance.

## Note — write-set observation

The four-host objective requires the PDF host's More wiring, and the only place the PDF
`BookDetailsUiModel` can be built is `PdfReaderActivity.kt` (the `PdfReaderChrome` composable
in the in-scope `PdfReaderScreen.kt` receives the model, but the Activity supplies it). The
brief's write-set named `reader/PdfReaderScreen.kt` for PDF but not `reader/PdfReaderActivity.kt`;
`PdfReaderActivity.kt` was edited minimally (mirroring the other three hosts) to complete the
objective. This is a reader-host file, not an orchestrator surface. Flagged in the HANDOFF.
