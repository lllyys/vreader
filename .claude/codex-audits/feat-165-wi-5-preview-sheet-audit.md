---
branch: feat/165-wi-5-preview-sheet
threadId: 019fd35d-aa55-7301-b4ae-25b9cee3aa58
rounds: 3
final_verdict: block-recommended
---

# Gate-4 audit — feature #165 WI-5 (`AnnotationImportPreviewSheet`)

Auditor: Codex `gpt-5.6-sol` via `scripts/run-codex.sh` (rule 53), read-only sandbox, three rounds.
Author/auditor separation held: the auditor is a separate process with no access to this session's
reasoning.

| Round | Thread | Verdict | Raw output |
| --- | --- | --- | --- |
| 1 | `019fd35d-aa55-7301-b4ae-25b9cee3aa58` | block-recommended | `.reports/audit-r1.txt` |
| 2 | `019fd36c-2292-72f2-beae-ddf52051ec5a` | block-recommended | `.reports/audit-r2.txt` |
| 3 | `019fd373-e78d-71c3-8334-d1d8d43d63a2` | block-recommended | `.reports/audit-r3.txt` |

Each round was asked four scope questions before the general audit: does any rendered count come
from anywhere but the envelope; is any visual state present that the bundle does not depict; is the
disabled state asserted as disabled rather than merely present; does anything add an export
affordance. Rounds 2 and 3 additionally had to verify the prior round's fixes were closed rather
than papered over.

## Outcome

**Round 3 is the cap and the verdict is still `block-recommended`, on ONE point** — the
zero-importable state's undesigned copy. Every implementation finding raised across the three rounds
is closed. The block is a design decision this lane is not authorised to make, so the work unit
returns as `blocked` rather than self-certified. Filed as **`needs-design` #2099**.

## Findings and disposition

### Round 1 (7 findings)

| # | Sev | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | High | The `Failed` arm rendered a provider-supplied file name straight to a pixel. Only the `Ready` arm's name had provably been through the reader; WI-7 constructs `Failed` from a name the reader may never see. | **FIXED** — `ImportFileHeader` sanitizes at the pixel for both arms via the shared idempotent `IncomingBookResolver.sanitizeDisplayName`. Tests: `failureState_sanitizesAProviderSuppliedFileName` (traversal + NUL + RLO), `failureState_survivesAnAllStrippedFileName`. Round 3: CLOSED. |
| 2 | High | An unbounded `bookTitle` in the merge line could push the action pair off the sheet. | **FIXED** — body scrolls, actions pinned. See round 2 #1 for the mechanism, which round 2 showed the first fix got wrong. |
| 3 | High | The zero-importable state is undesigned; a source-header rationale does not resolve it. | **ESCALATED** — `needs-design` #2099 filed. See "The block" below. |
| 4 | Medium | The header glyph was Material's `Description`, a self-directed substitution for the artboard's own `IconFileJson`. | **FIXED** — the design's exact path data (`:44-50`), `PathParser` + `Canvas`, 1.7 stroke in a 24-unit viewport. `theDesignedJsonGlyphActuallyDraws` captures the icon and asserts >1 colour, mutation-checked by blanking the path data. Round 3: CLOSED. |
| 5 | Medium | The no-export test forbade one tag and one literal string — false-greens on an icon-only or differently-worded affordance. | **FIXED** — `theOnlyTwoActionsAreCancelAndImport` enumerates every node with a click action and asserts the tag set is exactly `{annot-import-cancel, annot-import-confirm}`. Round 3: CLOSED. |
| 6 | Medium | "Nothing is re-derived" was literally false (`importable` is a sum inside `ImportPreview`). | **FIXED** — reworded to the true and still-load-bearing claim: this file computes no count of its own. Round 2: CLOSED. |
| 7 | Low ×4 | Merge-line-hidden assertion missing; no RTL / unknown-colour / null-title coverage; production file over 300 lines; comments overstate "only producer". | **FIXED** — production split three ways (223 / 249 / 191 lines); coverage added. Round 2: all CLOSED. |

### Round 2 (4 open)

| # | Sev | Finding | Disposition |
| --- | --- | --- | --- |
| 1 | High | Round 1's layout fix used a fixed `heightIn(max = 460.dp)` body cap. A constant cap looks right on a roomy host and pushes both actions off a small viewport at a large font scale. | **FIXED, and the auditor was demonstrably right**: `actionsStayReachableOnACompactViewportAtDoubleFontScale` (320×480 at `fontScale = 2.0`) was written first and **ran RED** against the capped layout — `annot-import-cancel is not displayed`. Replaced with `weight(1f, fill = false)` + `verticalScroll`, so the body takes the space that is LEFT. Round 3: CLOSED. |
| 2 | Medium | `sanitizeDisplayName` does an O(n) `lastIndexOf` over an arbitrarily large provider name on the composition thread. | **FIXED by DELETING the local heuristic.** Round 2's fix (`takeLast(4096)`) was itself wrong: round 3 showed that for a leaf longer than the bound it keeps the leaf's **suffix**, while the sanitizer's contract keeps the leaf's **prefix plus extension** — a local bound that changed the visible name to defend against something `IncomingBookResolver.boundedLeaf` already handles index-based, by design. The bound was removed rather than tuned; the residual is one O(n) index scan over a resident string, which is the shared sanitizer's shipped design, paid identically by the app's other SAF caller, and belongs in `imports/` (read-only for #165, plan §5.3) if it ever needs bounding. New test `failureState_keepsALongLeafsPrefixAndExtension` pins the restored contract with a surrogate pair astride the 200-character cap. |
| 3 | Medium | The glyph applied `StrokeCap.Round` to all three paths; the artboard rounds the CAP only on the braces and the JOIN only on the outline and fold. | **FIXED** — two `Stroke` styles. Round 3: CLOSED, "matches exactly". |
| 4 | Low | Test class oversized. | **PARTIALLY FIXED, remainder ACCEPTED.** Wire fixtures extracted to `AnnotationImportSheetFixtures.kt` (`SheetFx`, 133 lines) — the `AnnotationImportFixtures` / `AnnotationsImportApplierHarness` precedent. The class remains ~560 lines and was not split. Round 3 rejected the stated rationale on the grounds that several classes can share one connected invocation; in **this** harness they cannot — a comma-joined `class=A,B` fast-fails with `tests=0` (the #129/#133 observation the lane brief restates), and a `package=` filter would drag in unrelated annotation suites. Splitting therefore costs a real extra emulator invocation per run for zero isolation gain. Accepted as a Low with that rationale; all three PRODUCTION files are under 300 lines. |

### Round 3

Nothing new. #1 and #3 CLOSED; #2 addressed by the deletion above; #4 accepted; #5 (the design
block) OPEN by construction.

## The block — `needs-design` #2099

The auditor **accepted** the reading this lane put to it: in the artboard the `error` prop is not
"a failure occurred" but *"the explanation of why the count is zero"* — `Import 0 items` is rendered
**only** when `error` is truthy (`vreader-annotation-import.jsx:554`). So the zero-importable UI
state **is** depicted; what is missing is approved **copy**, and the mapping from the zero
conditions to it.

That matters because it narrows the blocker from "an undesigned state" to "undesigned text", and it
is why plan C-8's "the disabled primary **plus** the designed error blob explaining why" cannot be
implemented as written: no artboard and no shipped Android string supplies that copy. The shipped
failure vocabulary (`MainActivity.kt:59-64`) is `"Unsupported format: <name>"`, `"Couldn't open the
file"`, `"Import failed"` — all describing a failure that did not happen when a file reads perfectly
and merely has nothing new in it.

Zero-importable is reachable in ordinary use, not just adversarially: a re-import (every id already
present), an all-foreign-book file (C-1), a valid empty envelope (C-13, what exporting an
un-annotated book produces), or every row failing a row gate (C-7 tier 2).

The designer must decide three things, per the auditor:

1. the copy — one general explanation, or reason-specific text (already imported / nothing for this
   book / empty file);
2. whether the artboard's replacement behaviour stays canonical (the blob **replaces** the chips) or
   a zero-importable preview keeps its supporting counts;
3. whether the disabled primary keeps the literal `Import 0 items` label in the non-error cases.

**What ships in the interim, and why it is not an invention:** only depicted elements — the count
chips (so `Skipped: N` explains the zero), the merge-policy line, and the depicted **disabled**
`Import 0 items`, so the user provably cannot commit a no-op. Two absences are recorded in the
source ledger and pinned by tests (`emptyEnvelope_confirmIsDisabledAndTheEmptySampleSectionIsOmitted`,
`noBookmarksCountChip`) so neither is incidental and a later change goes RED.

## Mutation kill map (the tests were checked against deliberate defects, not assumed)

Each mutation was applied to the production source and the suite re-run on `emulator-5554`; the
named tests failed and nothing else did.

| Mutation | Killed by |
| --- | --- |
| A1 — primary count = `highlights + notes` (bookmarks forgotten) | `populatedPreview_confirmReadsImportableNotAnyOtherCount`, `intraFileDuplicates_confirmReadsTheCollapsedCount` |
| A4 — Skipped chip renders `sample.size` | `populatedPreview_chipsShowTheEnvelopeCounts`, `everythingAlreadyPresent_confirmIsDisabledAndInert` |
| A6 — a fourth "Bookmarks" chip added | `noBookmarksCountChip` |
| B2 — primary always `enabled = true` | `everythingAlreadyPresent_confirmIsDisabledAndInert`, `emptyEnvelope_confirmIsDisabled…`, `everyFailure_showsItsShippedMessageAndADisabledPrimary` |
| B3 — the error blob also renders on a `Ready` state | `populated_hasNoErrorBlob` |
| B5 — `onConfirm(preview.copy())` instead of the same instance | `confirm_handsBackTheSamePreviewObject` |
| C7 — the glyph's path data blanked | `theDesignedJsonGlyphActuallyDraws` |
| (audit-driven) the old fixed-height body cap | `actionsStayReachableOnACompactViewportAtDoubleFontScale` |

## Gates

- JVM: `RUN-ANDROID-TESTS RESULT: SUCCEEDED` — `:app:testDebugUnitTest --tests '*nnotation*'
  --rerun-tasks`, 208 tests, 0 failures, **0 skipped**.
- Connected (`emulator-5554`, one class per invocation): `RUN-ANDROID-TESTS RESULT: SUCCEEDED` —
  `AnnotationImportPreviewSheetTest`, **29 tests, 0 failures, 0 errors, 0 skipped**.
- Source scan: zero U+0000, C0/C1 controls or bidi-control code points in any of the five files
  (the hazard that materialised in WI-3).
