---
branch: feat/165-wi-7-saf-launchers
threadId: 019fd452-c0e5-7de2-b1a5-b336d529ee75
rounds: 4
final_verdict: follow-up-recommended
---

## Round 4 — orchestrator-run confirming round (2026-08-06): **VERDICT: clean**

Round 3 hit the rule-47 cap at `block-recommended` with one Medium open. Its fix landed in
`60eba8bd` **after** the verdict, and the lane returned `blocked` rather than certify its own fix.

**The Medium was a genuine Activity leak**: `ReaderActivity` passed
`onApplied = ::refreshAnnotationsSnapshot` — an Activity-bound method reference that the **app-scope**
apply job retained for the whole duration of the merge.

**Round 4 confirms the fix:**

- The durable app-scope job captures **only** `controller::apply`, `preview`, and a
  `CompletableDeferred`. `onApplied` is reached **only** from the composition-scoped waiter.
- **All four hosts use `applicationContext.contentResolver`** — no Activity-bound resolver reaches an
  app-scope job anywhere in the WI.
- **No regression**: the merge still survives composition teardown (the durable half is the point),
  `preview.importable == applied` remains covered, and WI-6's
  `assertDoesNotExist('details-export-annotations')` still passes.

**On the open Low** (the five `AnnotationImportSession` JVM tests exercise the session *object*, not
its *use* inside `rememberAnnotationImportEntry`, so deleting the composable's sheet guards would
leave them green): round 4 judged the lane's assessment **correct**, and shipping with it open
**acceptable for the import half**, given four-host connected reachability plus real round-trip
coverage. Closing it needs a fake-controller composable test with latched A/B previews and a latched
apply settle — carried as a follow-up.

`final_verdict` updated to `follow-up-recommended` on a clean independent confirmation, not an
override.

# Gate-4 implementation audit — feature #165 WI-7 (SAF import launcher + Gate-5b import acceptance)

Auditor: Codex `gpt-5.5`, reasoning effort `high`, read-only sandbox, driven through
`scripts/run-codex.sh` (rule 53). Author/auditor separation holds — the auditor is a separate
process with no access to this lane's reasoning.

Round transcripts (not committed; regenerated on demand):
`.reports/audit-r1.txt`, `.reports/audit-r2.txt`, `.reports/audit-r3.txt`.
Prompts: `.reports/audit-prompt-r{1,2,3}.txt`.

| Round | Codex session id | Verdict |
| --- | --- | --- |
| 1 | `019fd42b-1f35-7193-99f6-cfb1893c57f4` | 1 High, 1 Medium, 1 Low, 0 Critical |
| 2 | `019fd441-1f5a-7721-a936-6f5f82f13fb3` | 3 Medium, 1 Low (round-1 High confirmed fixed) |
| 3 | `019fd452-c0e5-7de2-b1a5-b336d529ee75` | **block-recommended** — 1 Medium, 1 Low open |

## Round 1

**High — the merge could be cancelled mid-flight.** `confirm` launched
`AnnotationsIoController.apply` on `rememberCoroutineScope()`. `AnnotationsImportApplier` rethrows
`CancellationException`, so a rotation / back press / `finish()` during the merge cancelled it, the
Room `@Transaction` rolled back, and nothing landed — after the user had already tapped
`Import N items`, with no surface to say so.
**Fixed** (`6c3aebbb`): the two phases take two scopes. The preview stays on the composition scope
(it writes nothing); the merge runs on `container.appScope`, passed by all four hosts as an explicit
`applyScope`. Extracted as `launchAnnotationImportApply` so the scope is a value a test can supply.
**Proven, not asserted** — MUTATION-7 put the apply back on the composition scope and
`eLargeImport_survivesTheReaderBeingFinishedMidMerge` went RED (66 s) while the other four stayed
green.

**Medium — "this is a WI-8-shaped export→import round trip".** Plan section 9.2 assigns the
export→import variant to WI-8. **Answered, not changed, and referred back to the auditor**: the
orchestrator's brief for this WI directs it to prove the real round trip using the in-process
writer, and a hand-assembled fixture would be strictly weaker (it cannot catch a writer/reader
disagreement). The class KDoc now states plainly that this does NOT discharge A-1/A-2's end-to-end
leg or A-10b — the export ENTRY POINT does not exist and stays `BLOCKED: needs-design #2085`.
**Round 2 accepted the disposition**: "honest and sufficient… It no longer claims more than the code
proves."

**Low — file size.** `AnnotationsRoundTripConnectedTest` was 531 lines. Split into a fixtures object.

## Round 2

**Medium — the import state machine was re-entrant.** With a slow provider: pick A, reopen Details,
pick B → whichever parse returns last wins; a double tap on `Import N items` queues a second merge;
dismiss-then-re-pick during a merge lets A's late settle clear B's sheet. Room's `IGNORE` keeps the
STORE consistent, so this is a "the sheet is showing the wrong pick" hazard, not a data one.
**Fixed** (`ad19971c`): `AnnotationImportSession` — one monotonic token; every user-initiated
transition (pick, dismiss) takes a new one, a merge claims the current one, an answer may only write
while its token is current. Five JVM tests, one per interleaving.
**Round 3 confirmed fixed**, interleaving by interleaving.

**Medium — Activity-bound `ContentResolver`.** Every host built the controller from the Activity's
resolver, and the app-scope merge captured the controller — retaining a finished Activity for as
long as an untrusted provider parked. **Fixed**: all four hosts pass
`applicationContext.contentResolver`. **Round 3 confirmed fixed at all four call sites.**

**Medium — the teardown test could pass while wrong.** It ASSUMED the ~700 ms merge window and never
observed it, so on a faster device even a composition-scoped apply would have passed.
**Fixed**: the test now samples the row count at the moment the reader reaches DESTROYED and fails
LOUDLY as *inconclusive* if the merge had already finished. **Round 3**: "better instrumented, not
deterministic… the row-count guard prevents a false pass when the merge already completed".

**Low — file size.** Test 531 → 325; production `AnnotationImportEntry` 315 → 191 by splitting the
pure half into `AnnotationImportEntryState.kt`.

## Round 3 — the cap. FINAL VERDICT: `block-recommended`

Two findings remain open at the round cap, so this WI returns **blocked** rather than
ready-for-integration (rule 47 Gate 4: max 3 rounds, then escalate).

### Medium (OPEN) — EPUB still captured the Activity in the app-scope settle lambda

`ReaderActivity` passes `onApplied = ::refreshAnnotationsSnapshot`, a method reference bound to the
Activity. The app-scope apply job retained the settle lambda — and through it that reference — until
the merge completed. Not a crash and not an untrusted-provider park, but the "nothing else captures
an Activity" claim was false.

**A fix has been APPLIED but is UNAUDITED** (`4b5c...`, the post-cap commit): `confirm` now splits
into two jobs — a DURABLE one on `applyScope` capturing only the controller, the preview and a
`CompletableDeferred`, and a COMPOSITION-SCOPED settlement job that awaits it and updates the sheet.
The merge is what had to survive and still does; the settlement dies with the reader, which is
correct because it only updates a sheet nobody is looking at.
**This lane does not certify its own fix** — the change is on the branch, all gates were re-run
green against it, and the orchestrator decides whether to accept it, re-audit it, or requeue.

### Low (OPEN) — the session tests exercise the session, not its use in the composable

Deleting the `sheet` guards inside `rememberAnnotationImportEntry` would leave the five
`AnnotationImportSession` tests green. Closing it needs a fake-controller composable test with
latched A/B previews and a latched apply settle. Not attempted in this WI.

## Mutation pass — every guard proven to fire

Each mutation applied alone against the committed tree, reverted immediately after; compile-error
count checked so a Kotlin failure could not be misread as a test failure.

| # | Mutation | Expected kill | Observed |
| --- | --- | --- | --- |
| 1 | `Azw3ReaderActivity` passes `onImportAnnotations = {}` (host discards the launcher) | that host's reachability test only | **4/4 → 1 RED**: `dAzw3Host…` RED (183 s), EPUB/TXT/PDF green |
| 2 | drop the `dispose` on the import `openInputStream` gate call | WI-4b's fd-leak cases | **20/20 → 2 RED**: `inputStreamProducedAfterTheDeadlineIsDisposed`, `aLateOpenedInputStreamIsDisposedEvenWhenTheRescueLaneIsSaturated` |
| 3 | applier receives an envelope the reader did not produce (`copy(notes = emptyList())`) | the `importable == applied` invariant | **10 RED across 2 suites**, incl. all 6 `AnnotationsImportApplierInvariantTest` cases |
| 4 | `ReaderChromeScaffold` drops `importSheet?.invoke()` | the three Compose-native hosts only | **5/5 → 1 RED**: TXT round trip RED (183 s), both EPUB tests green |
| 5 | `importPickerFileName` returns the RAW last path segment | the section-8.4 sanitization cases | **11/11 → 4 RED**: traversal, control/bidi, length cap, fallback |
| 6 | `EpubReaderSheets` drops `importSheet?.invoke()` | the EPUB tests only | **5/5 → 2 RED**: both EPUB round-trip tests RED, TXT + the controller-level A-9 test green |
| 7 | apply moved back onto the composition scope | the mid-merge teardown test only | **5/5 → 1 RED**: `eLargeImport_survivesTheReaderBeingFinishedMidMerge` RED (66 s) |

Mutations 1/4/6 are the discrimination pair-set: each kills exactly the hosts that route through the
mutated seam and leaves the others green, which is what makes "all four hosts are wired" a measured
claim rather than a grep.

## Gates at the audited commit

- JVM: `RUN-ANDROID-TESTS RESULT: SUCCEEDED` — 2381 tests / 0 failures / 0 errors / **0 skipped**.
- Connected `AnnotationImportReachabilityTest`: 4 / 0 / **0 skipped** (EPUB, TXT, PDF, AZW3).
- Connected `AnnotationsRoundTripConnectedTest`: 5 / 0 / **0 skipped**.
- Regressions: `AnnotationsIoEntryTest` 12/0 (incl. WI-6's `assertDoesNotExist` export guard),
  `EpubReaderChromeTest` 3/0.
- Known pre-existing RED, NOT this WI's: `ReaderChromeScaffoldTest.bookmarksRoute_rendersNoUndesignedSurface`
  (bug #372 / GH #2103) — 15/16 pass; the WI-6 lane proved it fails on the untouched branch HEAD.
