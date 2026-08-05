---
branch: feat/165-wi-6-details-rows
threadId: 019fd3e2-8f46-7773-b502-a93f23469d1b
rounds: 2
final_verdict: follow-up-recommended
---

# Gate-4 audit — feature #165 WI-6 (Book Details import row + merge-policy footnote)

Auditor: Codex `gpt-5.5`, reasoning effort `high`, read-only sandbox, via `scripts/run-codex.sh`
(rule 53). Author/auditor separation preserved — the implementing session never certified its own
fix to a finding; every claimed fix went back to the auditor in round 2.

- Round 1 thread: `019fd3e2-8f46-7773-b502-a93f23469d1b` — raw output `.reports/audit-r1.txt`
- Round 2 thread: `019fd3e9-98b2-7393-b398-1af4f0967bc2` — raw output `.reports/audit-r2.txt`

## Scope

WI-6 ships the designed **`Import annotations…`** `ActionList` row plus B1-paired's merge-policy
footnote on the Book Details sheet, threaded through **both** production chrome hosts, plus the
rule-22 KDoc repairs. The paired **`Export annotations…`** row is deliberately NOT built —
`BLOCKED: needs-design (#2085)`, WI-8.

Files audited:

- `android/app/src/main/kotlin/com/vreader/app/reader/details/BookDetailsRows.kt`
- `android/app/src/main/kotlin/com/vreader/app/reader/details/BookDetailsSheet.kt`
- `android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderChromeScaffold.kt`
- `android/app/src/main/kotlin/com/vreader/app/reader/EpubReaderChrome.kt`
- `android/app/src/main/kotlin/com/vreader/app/annotations/Annotation.kt` (comment-only)
- `android/app/src/main/kotlin/com/vreader/app/data/Entities.kt` (comment-only)
- `android/app/src/androidTest/kotlin/com/vreader/app/annotations/AnnotationsIoEntryTest.kt` (new)

## The four directed questions

1. **Is the Import row production-reachable?** The auditor traced the chain independently and
   returned the honest answer: the capability chain is complete and correct (top-bar More →
   `ReaderSheet.Details` → `BookDetailsSheet` → the row, in both hosts), but **WI-6 alone does not
   make the row user-reachable in a shipped build** — the four production call sites
   (`ReaderActivity.kt:931`, `TxtReaderActivity.kt:1557`, `PdfReaderScreen.kt:164`,
   `Azw3ReaderChrome.kt:156`) still pass nothing. That is exactly the plan's WI-6/WI-7 split
   (§5.2, §10): WI-6 plumbs the capability, WI-7 wires the entry points, and acceptance criterion
   **A-10a** belongs to WI-7. Recorded here so nobody reads WI-6 as delivering reachability.
2. **Does any export affordance exist?** No. Hard grep found no `onExportAnnotations`, no
   `details-export-annotations` production tag, no export row / menu id / icon branch. Every
   `Export annotations…` hit is a comment or a negative test assertion.
3. **Is `assertDoesNotExist("details-export-annotations")` load-bearing?** Yes — it is paired with
   positive Import assertions in the same test, so it cannot pass because the sheet failed to
   render. Residual (accepted): it would not catch a differently-labelled export affordance such as
   "Save annotations…"; it does catch the planned tag and the exact designed label.
4. **Can a test pass if a chrome host discards the callback?** The six sheet-level tests would —
   which is the whole point of the two host tests. `scaffoldHost_detailsRoute_importRowFiresHostCallback`
   and `epubHost_detailsRoute_importRowFiresHostCallback` are the guards for the #140 WI-6
   discarded-callback shape; the mutation pass below proves they fire.

## Findings and disposition

| # | Sev | Finding | Disposition |
|---|---|---|---|
| R1-1 | **Medium** | `Entities.kt:80` — the `HighlightEntity` KDoc still claimed the backup collector "MUST convert" `locatorJSON` to `canonicalJson()`, contradicting `AnnotationBackupMapper` (`BackupJson.encode(locator)`). **A third stale site the plan's W15 never cited** (W15 named only `Annotation.kt:8-9`, `Entities.kt:112`, `:120-121`). | **FIXED**, then **independently re-verified in round 2**: auditor re-read all three files, grepped `android/app/src/main` + `android/identity`, and confirmed every surviving `canonicalJson()` mention is a `profileKey` hashing input or an explicit negation. Closed. |
| R1-2 | Low | The host tests forced `sheet = ReaderSheet.Details` directly, so a broken More → Details transition would have passed. | **FIXED**: added `scaffoldHost_fullMoreToDetailsToImport_firesHostCallback` and `epubHost_fullMoreToDetailsToImport_firesHostCallback`, which start at `ReaderSheet.None` and walk `chrome-more` → `more-row-details` → `details-import-annotations`. Round 2 confirmed closed for both hosts. Proven load-bearing by MUTATION-5. |
| R1-3 | Low | `BookDetailsRows.kt` is 387 lines vs the repo's ~300 guideline; `BookActionList`/`ActionRow` is a clean split candidate. | **ACCEPTED with rationale, not fixed.** Creating `details/BookDetailsActions.kt` is a write-set expansion this lane does not own (rule 55). 32/279 files in this module already exceed 300, and the change *reduced* duplication by extracting the shared `ActionRow`. Round 2 agreed the acceptance is reasonable and non-blocking. **Proposed as an orchestrator-owned follow-up.** |

Round 2 raised **no new Critical/High/Medium/Low findings**.

## Mutation pass (the kill map — every guard proven to fire)

Each mutation was applied alone, run on `emulator-5554`, and reverted. Compile-error count was
checked on every run (`grep -c "^e: "` on the wrapper log) so a Kotlin compile failure could never be
misread as a test failure — the WI-4b hazard. The first attempt at MUTATION-1 *was* a compile
failure (`false && x != null` defeats the smart cast) and was rewritten as a behaviour-only
mutation before being counted.

| Mutation | Result | Reads as |
|---|---|---|
| Delete the Import `ActionRow` call | **6/10 RED** | the 4 survivors are the four absence/Share-only tests, which *should* stay green — the count is exactly right |
| Add an `Export annotations…` row (`details-export-annotations`) | **4/10 RED** | every RED is an export-absence guard; the `assertDoesNotExist` is load-bearing, not filler |
| Drop the merge-policy footnote | **3/10 RED** | footnote test + both host tests |
| Both chrome hosts accept `onImportAnnotations` and discard it | **exactly 2/10 RED** — the two host tests; all six sheet-level tests stayed GREEN | the #140 WI-6 defect shape, caught precisely by the tests written for it and invisible to sheet-only tests |
| Break the EPUB `More → Details` transition | **exactly 1/12 RED** — only `epubHost_fullMoreToDetailsToImport…`; the pre-opened-sheet EPUB test stayed GREEN | proves the R1-2 gap was real and that the audit-driven fix closes it precisely |

## Test evidence

- Connected, `emulator-5554`: `AnnotationsIoEntryTest` — **12 tests, 0 failures, 0 errors, 0 skipped**
  (`RUN-ANDROID-TESTS RESULT: SUCCEEDED`; counts read from the result XML with an mtime freshness
  check, not from the exit code).
- JVM: `:app:testDebugUnitTest --tests '*nnotation*' --tests '*BookDetails*' --rerun-tasks` —
  **265 tests, 0 failures, 0 errors, 0 skipped**.
- Connected regressions: `BookDetailsSheetTest` **14/0/0**, `EpubReaderChromeTest` **3/0/0**.
- One class per connected invocation; `--rerun-tasks` on every run.

## Pre-existing failure surfaced (NOT caused by this WI, NOT fixed here)

`ReaderChromeScaffoldTest.bookmarksRoute_rendersNoUndesignedSurface` fails: 16 tests / 1 failure.
It asserts the `ReaderSheet.Bookmarks` route renders nothing, but #135 WI-6 made that route render
`TocBookmarksSheet` (`ReaderChromeScaffold.kt:250`) — the test is a stale #135 WI-5 assertion that
was never re-run after WI-6 landed. **Proven pre-existing**: the identical failure reproduces on the
untouched branch HEAD (`git stash` → same 16/1 → `git stash pop`). This is the "connected tests
merged compile-only are UNVERIFIED until the Gate-5 connected run" class (#133/#135 precedent).
Left unfixed deliberately — it is #135's debt, out of this feature's scope, and silently rewriting
another feature's assertion would destroy the signal. Reported to the orchestrator for a bug row.

## Control-byte scan

All seven written files scanned byte-wise for U+0000, C0/C1 controls, DEL, the enumerated bidi
overrides, and zero-width/BOM characters: **0 NUL, 0 suspicious** in every file.

## Verdict

**follow-up-recommended** — ship WI-6; carry the accepted Low (file split) and the surfaced
pre-existing `ReaderChromeScaffoldTest` failure as orchestrator-owned follow-ups.
