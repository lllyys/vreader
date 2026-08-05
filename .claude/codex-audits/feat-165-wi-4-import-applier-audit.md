---
branch: feat/165-wi-4-import-applier
threadId: 019fd2e9-6a08-7c10-ae83-dd00119df087
rounds: 2
final_verdict: follow-up-recommended
---

# Gate 4 — feature #165 WI-4, `AnnotationsImportApplier`

Auditor: Codex (`gpt-5.6-sol`) via `scripts/run-codex.sh` (rule 53).
Round 1 thread `019fd2df-7e63-7d20-807a-e78fb1e93ec4` → **block-recommended**.
Round 2 thread `019fd2e9-6a08-7c10-ae83-dd00119df087` → **follow-up-recommended**.
Raw transcripts: `.reports/audit-r1.txt`, `.reports/audit-r2.txt` (not committed).

## Round 1 — block-recommended

| # | Sev | Finding | Disposition |
|---|---|---|---|
| 1 | High | `existingState` scoped ids to the target book, but every annotation table's PRIMARY KEY is the id ALONE, so ids are unique **library-wide**. A row reusing another book's UUID was previewed as importable and then silently IGNOREd — a real `preview.importable == applied` divergence. | **FIXED.** RED test first (`importableEqualsApplied_whenAnIncomingIdIsAlreadyUsedByAnotherBooksAnnotation`) failed **6 vs 3**; `existingState` now collects ids from `allHighlights`/`allNotes`/`allBookmarks` library-wide, position keys stay target-book-scoped. Round 2 confirmed closed. |
| 2 | Medium | The corrupt-stored-row residual is wider than documented: a corrupt row hides **both** its primary-key id and its stored unique-index key. | **DOCUMENTED, follow-up.** The fix (DAO projections reading raw ids/unique columns without decoding `locatorJSON`) requires `AnnotationDao`/`AnnotationsRepository`, outside this WI's write set. Round 2: "bounded and non-destructive, should not block WI-4". Its wording correction (a highlight's key is `(profileKey, anchorKey)`, not "position key") was applied verbatim. |
| 3 | Medium | The claimed *structural* atomicity ("all rows share one `bookKey`, so a partial apply is unreachable") is **wrong** — the green `@Transaction` mutation is a test gap, not redundancy. | **FIXED (claim deleted).** The header now states atomicity comes from `@Transaction`, that these tests do not prove it, and that a partial apply remains reachable via cancellation, a later non-constraint failure, or delete-recreate. Round 2: "the corrected wording is accurate". |
| 4 | Low | Test file over the ~300-line convention (363 lines). | **FIXED.** C-5b + error-mapping split into `AnnotationsImportApplierBookMissingTest.kt`. All five files now 126–286 lines. Round 2 confirmed no coverage lost or duplicated and both discriminators still work. |

Round 1 also confirmed: the layer-2 test genuinely reaches the FK mapping (layer 1 cannot produce a
`SQLiteConstraintException` cause); mapping all `SQLiteConstraintException` is correct under this
schema because `ON CONFLICT` does not absorb FK violations while PK/UNIQUE/NOT NULL/CHECK are
IGNOREd; the `CancellationException` catch ordering is right; no skipped row can be inserted.

## Round 2 — follow-up-recommended (open items, all outside this WI's write set)

- **Medium** — corrupt persisted rows stay invisible to `existingState` (round-1 #2). Follow-up: DAO
  projections for raw ids + raw unique-index columns, plus corrupt-row integration tests.
- **Medium** — transactional rollback is still unverified; neither C-5b test fails when
  `@Transaction` is removed. Follow-up: a DAO fault-injection seam that fails on a *later* insert
  and asserts the full pre-apply snapshot is restored.
- **Low** — the library-wide id read costs three full-table reads that decode every locator and
  materialise every highlight text / note body. Correctness sound; fix alongside the DAO projections.

All three converge on ONE follow-up in `AnnotationDao`/`AnnotationsRepository` — a seam this work
item may not write. Recorded rather than silently carried.

## Mutation evidence (the kill map)

Each mutation applied to the shipped code, gate re-run, then reverted.

| # | Mutation | Result |
|---|---|---|
| M1 | drop the layer-2 `SQLiteConstraintException` → `BookMissing` mapping | **KILLED** — only the 2 layer-2 tests RED; both layer-1 tests green |
| M2 | drop the layer-1 `findBook` pre-check | **KILLED** — only `layer1_isTheRefusal_evenWhenTheInsertItselfWouldHaveSucceeded` RED; layer 2 green |
| M3 | `existingState` drops highlight position keys | **KILLED** — 3 tests RED incl. `importableEqualsApplied_againstAPopulatedDatabase` |
| M4 | drops bookmark position keys | **KILLED** — 3 RED |
| M5 | drops note ids | **KILLED** — 3 RED |
| M6 | drops the book scope on bookmark position keys | **KILLED** — `existingState_positionKeysAreScopedToTheBook_butIdsAreLibraryWide` RED |
| M7 | widen `allowedBookKeys` to whatever the file asks for | **KILLED** — 2 RED (foreign-book rows would insert) |
| M9 | re-scope ids to the target book (the round-1 defect) | **KILLED** — 2 RED |
| M8 | remove `@Transaction` from `AnnotationDao.restoreAnnotationEntities` | **SURVIVED** — see round-1 #3; a genuine test gap, follow-up named above. `Daos.kt` verified byte-identical to HEAD afterwards. |

M1 and M2 together are the required proof that the two C-5b layers are independently tested: each
mutation reddens exactly one layer's test and leaves the other's green.
