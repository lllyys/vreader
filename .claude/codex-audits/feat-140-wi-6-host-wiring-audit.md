---
branch: feat/140-wi-6-host-wiring
threadId: 019fd18b-a262-7cc0-8887-fc5452b7e123
rounds: 3
final_verdict: follow-up-recommended
date: 2026-08-05
---

# Codex Audit Log — Feature #140 (GH #2064) WI-6: AZW3 Contents host wiring

Gate 4 for the WI that makes the Contents (table-of-contents) control **appear**
on the AZW3/MOBI/KF8 reader. Everything before it was plumbing a user could not
reach.

Plan: `dev-docs/plans/20260805-feature-140-android-azw3-toc.md` (`id: WI-6`).
Auditor: Codex `gpt-5.5`, reasoning `high`, read-only sandbox, via
`scripts/run-codex.sh` (rule 53). Author ≠ auditor (rule 48).

Round transcripts: `.reports/audit-r1.txt`, `.reports/audit-r2.txt`,
`.reports/audit-r3.txt` (worktree-local, not committed).

| Round | Thread | Commit audited | Verdict |
| --- | --- | --- | --- |
| 1 | `019fd17a-1ea9-7bc0-b494-0ce246bee2e0` | `71f934f2` | block-recommended (3 Medium, 2 Low) |
| 2 | `019fd183-622f-7951-8cbf-9f4260d2737c` | `cb377566` | follow-up-recommended (2 Low) |
| 3 | `019fd18b-a262-7cc0-8887-fc5452b7e123` | `173a7313` | follow-up-recommended (2 Low) |

**Final state: zero open Critical/High/Medium across the WI** (round 3, verbatim:
"No new Critical/High/Medium finding introduced by `173a7313`. No
Critical/High/Medium finding remains open across the WI."). Two Low findings
remain, both dispositioned below.

## Scope of audit

The 8-file diff of WI-6 across three commits (`git diff HEAD~3`):

- `android/app/src/main/kotlin/com/vreader/app/reader/foliate/Azw3Document.kt`
- `android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderActivity.kt`
- `android/app/src/main/kotlin/com/vreader/app/reader/Azw3ReaderChrome.kt`
- `android/app/src/main/kotlin/com/vreader/app/reader/chrome/ReaderBottomChrome.kt`
- `android/app/src/main/kotlin/com/vreader/app/reader/nav/EmptyTocProvider.kt` (comment-only)
- `android/app/src/main/kotlin/com/vreader/app/reader/nav/TocProvider.kt` (comment-only)
- `android/app/src/androidTest/kotlin/com/vreader/app/reader/Azw3ReaderChromeUiTest.kt`
- `android/app/src/test/kotlin/com/vreader/app/reader/nav/FoliateTocProviderTest.kt`

The prompts asked four targeted questions beyond the standard sweep, each of
which names a way this WI could pass while being wrong.

## The four targeted questions

**1. Production reachability.** Confirmed by call-site trace, not assertion:
`AndroidManifest.xml` LAUNCHER → `MainActivity.openBook` routing
`BookFormat.azw3` → `Azw3ReaderActivity.intent` → `LibraryScreen`'s `onOpen` →
`Azw3Document.Loaded(sectionTotal, toc)` → `Azw3ReaderHost`'s `onToc` → the
activity's flatten → `Azw3ReaderChrome` → `ReaderChromeScaffold`'s non-empty-TOC
callback → `chrome-contents`. Every file on that path is in
`android/app/src/main`. (Rule 47's Gate-5 precedent: four Android features
shipped `VERIFIED` with composables that had zero production call sites.)

**2. Could a test pass with the bug still present?** The load-bearing question
for this WI, because the defect was a discarded callback
(`bottomChrome = { _, onOpenNotes -> … }`) that a stubbed bottom chrome would
hide. Auditor confirmed no test stubs the chrome — all 14 drive the real
`Azw3ReaderChrome` → `ReaderChromeScaffold` → `Azw3BottomChrome` stack — and
identified `nonEmptyToc_showsContentsControl`,
`tappingContents_opensSheet_listingEveryChapterTitle` and
`contentsAndNotes_bothRenderInTheDesignedOrder` as the three with teeth against
that exact defect.

This was also demonstrated empirically before implementation: with the params
added but the `_` discard left in place, a full connected run put exactly those
three RED (12 tests, 3 failures, 0 skipped) while the sheet-behaviour tests
passed. That is the RED of this WI.

**3. Ack is not motion.** foliate's `view.goTo` swallows a failed resolution and
acks `ok:true` anyway, so no ack proves the reader moved. Round 1 found the test
KDoc correct but several production comments still saying a jump "landed";
rounds 2 and 3 drove that out of the entire #140 path. No new assertion equates
an ack, a `JumpResult.Succeeded`, or a sheet dismissal with navigation. Actual
motion is WI-7's real-book connected round-trip against a later relocate's
reported position.

**4. Slot-treatment drift.** The Contents slot uses the *same*
`ToolbarIconButton` as EPUB/TXT (promoted `private` → `internal`), with
identical icon, label, testTag, semantics, padding and tint; ordering is
Contents before Notes, per the design. The enclosing bar differs by design (no
scrubber, no Display — AZW3 has neither). Auditor: promoting is the right call;
duplicating "would make drift easier".

## Round 1 findings and dispositions (commit `cb377566`)

| # | Sev | Finding | Disposition |
| --- | --- | --- | --- |
| M1 | Medium | `runCatching { provider.toc() }` also catches `CancellationException`, so a flatten cancelled by a book change or by the effect leaving composition would publish `emptyList()` — blinking the Contents control off, or clobbering the next book's rows | **FIXED.** Replaced with `try/catch` that rethrows `CancellationException` before degrading a genuine `Exception` to `emptyList()`. Round 2: FIXED, catch order verified correct |
| M2 | Medium | `docs/architecture.md` is in the plan's WI-6 write-set but unmodified; it still says `EmptyTocProvider (PDF/AZW3)` and that WI-6 host wiring has not landed | **ACCEPTED — orchestrator-owned.** Rule 55 makes `docs/architecture.md` a shared surface removed from this lane's write-set; a lane editing it breaks the single-writer lock model. The exact replacement lines travel in the HANDOFF's `docs_sync` (covering the #140 lines **and** the separately-stale #139 sentence at `:661-663`). Round 2: ACCEPTED-WITH-RATIONALE-**OK**, with the standing condition that the orchestrator apply it before merge |
| M3 | Medium | The plan's acceptance requires "render-death mid-session keeps the TOC visible and degrades a jump to Failed", untested | **FIXED (behaviour) + adjudicated (structure).** The jump half is now the named pure `azw3TocJumpDecision(document, entries, index)` with two connected tests. The "rows stay visible" half I claimed was structural; round 2 was asked to **verify that itself rather than take my word**, and did: `tocEntriesState` is keyed only on `bookKey`, `reloadKey` recreates only the holder/WebView, and `onToc` fires only on `Loaded` — so entries genuinely survive a recreate. "No High" |
| L1 | Low | Stale comment still claiming "AZW3 has no reader TOC" in the bookmark wiring | **FIXED.** Rewritten to state why bookmark *rows* still project no chapter label (href-keyed TOC vs cfi/fraction-anchored bookmark). Round 2 verified the new claim is true |
| L2 | Low | `Azw3ReaderActivity.kt` over the ~300-line guideline (513 lines) | **ACCEPTED.** Splitting requires a NEW file, outside this lane's declared write-set; the file was already 422 lines before this WI. Round 2: ACCEPTED-WITH-RATIONALE-OK, "not worth blocking this lane". Named follow-up |

## Round 2 findings and dispositions (commit `173a7313`)

| # | Sev | Finding | Disposition |
| --- | --- | --- | --- |
| L3 | Low | `tocJumpDecision_withAnOutOfRangeIndex_fails` only ever passed `document = null`, so every leg returned Failed for the null-document reason alone — it would false-green on an implementation that never validated the index | **FIXED.** Now runs against a real (constructed-only) `Azw3Document`, with an in-range `Succeeded` **control** that gives the Failed cases their meaning, plus an href-less row as a third distinct Failed reason. Round 3 verified it "genuinely distinguishes index validation from the null-document short circuit" |
| L4 | Low | Ack-is-not-motion wording only partially fixed | **FIXED for the #140 path** (`Azw3Document.goTo` KDoc, the bookmark-jump comment). See L6 for the residue |

## Round 3 findings and dispositions (final)

| # | Sev | Finding | Disposition |
| --- | --- | --- | --- |
| L5 | Low | The new `withLiveDocument` helper's KDoc claims construction is side-effect-free, but `FoliateGoToDispatcher.init` launches an ack collector on a standalone `CoroutineScope(Dispatchers.Main)` that `webView.destroy()` does not cancel | **COMMENT FIXED; leak accepted.** The claim was mine and false, so the KDoc now states the truth precisely — the collector is idle (it observes a `SharedFlow` nothing emits to, since no bridge is attached), affects none of the other 13 tests, but is not a clean teardown. The auditor explicitly rated this **not** a Medium blocker. The logic was NOT changed post-cap. Follow-up: the auditor's own suggestion — a boolean "is there a live document" seam that removes the WebView dependency from a pure decision test |
| L6 | Low | Residual "landing" wording in the **pre-existing #135 bookmark** path (`landed` local, "awaited landing", "re-lands the position") | **ACCEPTED.** Not #140 code and not on the TOC path; renaming a local in the bookmark jump would be a drive-by refactor (AGENTS.md "keep diffs focused"). Surfaced only because I asked the auditor for an exhaustive sweep across the whole file rather than the diff. Named follow-up |

## Named follow-ups (not blocking)

1. **`docs/architecture.md`** — the orchestrator applies the `docs_sync` lines,
   including the stale **#139** sentence at `:661-663` that this WI did not
   create but does neighbour.
2. **Split `Azw3ReaderActivity.kt`** (513 lines) — needs a new file, so it needs
   a write-set that authorises one.
3. **A WebView-free seam for `azw3TocJumpDecision`** so the pure decision test
   stops constructing an `Azw3Document`.
4. **Retire the residual "landing" vocabulary in the #135 bookmark path.**

## Test evidence at the audited HEAD

- JVM: `RUN-ANDROID-TESTS RESULT: SUCCEEDED` — **373 tests / 0 failures / 0
  errors / 0 skipped** across 25 classes
  (`--tests '*Foliate*' --tests '*Toc*' --tests '*Azw3*' --tests
  '*BookmarkHostWiring*' --rerun-tasks`).
- Connected (`Azw3ReaderChromeUiTest`, emulator-5554):
  `RUN-ANDROID-TESTS RESULT: SUCCEEDED` — **14 tests / 0 failures / 0 errors /
  0 skipped**. Counts read from the JUnit XML, never from `BUILD SUCCESSFUL`.
- Regression, one class per invocation: `Azw3BookmarkNavTest` 5/0/0 skipped,
  `ReaderBottomChromeSlotsTest` 4/0/0 skipped, `SearchHiddenOnPdfAzw3Test`
  2/0/0 skipped.
- The real AZW3 fixture (`androidTest/assets/foliate-spike/book.azw3`,
  6,288,371 B) was staged into the worktree, so the AZW3 classes **ran** rather
  than `assumeTrue`-skipping.

### Pre-existing failure, NOT caused by this WI

`Azw3ReaderActivityTest.tappingNext_turnsThePage_advancesPosition` fails on this
emulator with *"The component with TestTag = 'azw3-next-zone' is not
displayed!"*. It was bisected rather than assumed: `git checkout HEAD~1 --
android` reproduced the identical failure at WI-5 HEAD with none of this WI's
changes present (the other two tests in the class pass, so the fixture path is
sound). It is invisible in normal lane runs because the gitignored fixture is
absent from a fresh worktree and the class `assumeTrue`-skips. Reported as a
residual in the HANDOFF for the orchestrator to file.
