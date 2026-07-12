---
branch: feat/133-wi12-search-hidden
threadId: 019f53cc-4a9d-7653-be8a-913d79289a5f
rounds: 1
final_verdict: ship-as-is
---

# Gate-4 Codex audit — feature #133 WI-12 (`SearchHiddenOnPdfAzw3Test`)

## Scope

New Android instrumented Compose regression test, test-only WI (the feature is
already DONE + merged through WI-11). No production code changed.

- File under audit: `android/app/src/androidTest/kotlin/com/vreader/app/reader/SearchHiddenOnPdfAzw3Test.kt`
- Ground-truth reference files (read-only): `chrome/ReaderTopChrome.kt`,
  `chrome/ReaderChromeScaffold.kt`, `PdfReaderScreen.kt` (`PdfReaderChrome`),
  `Azw3ReaderActivity.kt` (`Azw3ReaderChrome`), and the sibling
  `PdfReaderChromeUiTest.kt` / `Azw3ReaderChromeUiTest.kt` patterns.

## What the test asserts

The reader top-bar **Search** control (`chrome-search` testTag) is HIDDEN on the
PDF and AZW3 reader hosts because in-book search is unsupported for those formats
(WI-7's `IndexStateGate` → `Unsupported`). Neither `PdfReaderChrome` nor
`Azw3ReaderChrome` forwards an `onOpenSearch` into `ReaderChromeScaffold`, so the
scaffold's `onSearch` stays null and `ReaderTopChrome` never renders `chrome-search`
(the #129 no-dead-control rule). The test renders each host chrome directly and
asserts `chrome-search` absent, with `reader-top-chrome` + `chrome-back` +
`chrome-notes` present as positive controls.

## Round 1 — findings

- **Critical / High / Medium**: none.
- **Low**: none actionable. The only noted theoretical gap is full Activity-level
  wiring; the auditor concluded an Activity-level test adds little regression value
  here because these chrome composables offer NO `onOpenSearch` parameter — the
  omission is structurally enforced.

### Auditor conclusions (verbatim summary)

1. False-green protection is sound: both cases assert `reader-top-chrome`,
   `chrome-back`, and `chrome-notes` exist BEFORE asserting zero `chrome-search`
   nodes — proving the shared top chrome + host-specific bottom chrome rendered.
2. Correct production paths are exercised: the test directly renders the same
   internal `PdfReaderChrome` / `Azw3ReaderChrome` composables production uses, with
   valid current signatures + arguments matching the sibling UI tests.
3. Tags + absence assertion correct: `reader-top-chrome`/`chrome-back` come from
   `ReaderTopChrome`; `chrome-search` is attached only when `onSearch != null`;
   the format Notes toolbars attach `chrome-notes`;
   `onAllNodesWithTag(...).assertCountEquals(0)` is the appropriate non-existence
   assertion; `useUnmergedTree = true` is consistent across positive + negative checks.
4. Compose-test setup is valid (AndroidJUnit4 runner, Compose rule, `setContent`,
   imports, mutable state, semantics-tree selection).

## Verdict

**ship-as-is** (1 round). Long output: `.reports/audit-r1.txt`.
