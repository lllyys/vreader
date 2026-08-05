---
branch: feat/165-wi-2-export-writer
threadId: 019fd248-c745-7383-8f0e-5ee08b0e7e78
rounds: 2
final_verdict: follow-up-recommended
date: 2026-08-05
---

# Codex Audit Log — Feature #165 WI-2 (`AnnotationsExportWriter`)

Gate 4, in-lane, `scripts/run-codex.sh` (rule 53), model `gpt-5.6-sol`, effort `high`,
read-only sandbox. Author/auditor separation held: the lane authored, Codex audited.

Scope (the lane's entire write set):

- `android/app/src/main/kotlin/com/vreader/app/annotations/AnnotationsExportWriter.kt`
- `android/app/src/test/kotlin/com/vreader/app/annotations/AnnotationsExportWriterTest.kt`

Round transcripts: `.reports/audit-r1.txt`, `.reports/audit-r2.txt` (not committed — they
carry the full tool trace; the findings and dispositions below are the record).

## Round 1 — session `019fd248-c745-7383-8f0e-5ee08b0e7e78`

Asked specifically: does any path build wire JSON outside `AnnotationBackupMapper`; is the
schema-version assertion on the value or the type; is any conformance assertion circular;
does the contract-vector check actually discriminate.

**Answers.** (1) No — `exportJson` and `writeTo` both reach `Rows.json`, the file's only
serialization call, which is `AnnotationBackupMapper.json`; the collector passes its
filtered records to the same mapper, so the bytes coincide for a stable row set.
(2) The value, twice — the decoded envelope's `schemaVersion` and the raw JSON integer are
both asserted `== BackupSchema.CURRENT_SCHEMA_VERSION`; a `schemaVersion = 1` export is
caught (and would also break both byte goldens). (3) The goldens are **not** circular: the
auditor compared them character-for-character against
`AnnotationBackupMapperTest.GOLDEN_SECTION` and confirmed exact equality with that section
filtered by `bookFingerprintKey` — 1,831/1,831 characters for book A, 924/924 for book B.
The contract-vector check is independent (it derives everything from the committed vector).
`exportJson_equalsTheSharedMappersOutputForTheSameRows` **is** circular for wire
correctness — see Low 1. (4) The vector check discriminates key names, container/primitive
types, unknown keys and required keys, but would still pass `schemaVersion = 1`, blanked
`selectedText`, wrong ids/colors, wrong ordering, or rows on the wrong book; the byte
goldens and the field-by-field repository comparison are what catch those.

Findings: **0 Critical, 0 High, 1 Medium, 3 Low.**

| # | Sev | Finding | Disposition |
| --- | --- | --- | --- |
| M1 | Medium | The three kinds are not captured in one database snapshot (`rows()` reads highlights+notes via `annotationsForBook`, then bookmarks separately; `annotationsForBook` is itself two non-transactional queries), so a concurrent commit can yield a hybrid export. | Re-graded to Low in round 2 — see below. Fix is out of this lane's write set. |
| L1 | Low | `exportJson_isTheSharedMappersText`'s KDoc overstated what it proves (hand-built but byte-identical text would pass; its expected value comes from the same mapper). | **Fixed** — renamed `exportJson_equalsTheSharedMappersOutputForTheSameRows`; KDoc now states it is same-rows output equivalence, that it cannot prove delegation, and that the goldens are the independent evidence. |
| L2 | Low | `flush()` implemented but not tested — `ByteArrayOutputStream` surfaces bytes without a flush, so removing `sink.flush()` left the suite green. | **Fixed** — the tracking sink now records the write/flush/close event sequence. |
| L3 | Low | The test file exceeds the ~300-line guideline. | **Accepted with rationale**, auditor concurred in round 2 (see below). |

## Round 2 — session `019fd253-fbf6-7912-8309-a333a656dc73`

The Medium was put back to the auditor with the facts it had not weighed, and with an
explicit instruction not to downgrade to be agreeable: the lane's write set is exactly two
files (the fix needs `data/Daos.kt` + `AnnotationsRepository.kt`, owned elsewhere under
rule 55); the non-transactional `annotationsForBook` is the shipped #132 WI-6b read, not
introduced here; the exported file is an idempotent per-row merge payload; the plan itself
accepts an analogous TOCTOU residual on the import side (plan:587-593) and nowhere requires
an atomic cross-kind export snapshot (C-12, C-13, A-1, A-2 specify kinds, sorting, schema,
row equality and shape); and the writer has no production call site until WI-8.

**Verdict on M1: re-graded Medium → Low, explicitly "not a WI-2 blocker".** The auditor's
reasoning: every emitted row stays valid and self-consistent (no cross-kind referential
invariant, no overwrite, no invalid envelope); C-12/A-1/A-2 do not require snapshot
isolation; the existing backup collector has the same sequential cross-kind behaviour, so
this is a pre-existing repository limitation rather than a WI-2 defect; and real isolation
needs a shared `@Transaction` DAO query + repository API that should cover export **and**
backup together — a separate follow-up.

The auditor named one lane-local mitigation, which was applied: **document the guarantee
accurately** so no downstream WI assumes a point-in-time snapshot it does not get. The
`rows()` KDoc and the file header now state that the kinds are captured through sequential
one-shot reads and that byte identity applies to the captured row set.

Also applied from round 2: the flush test now asserts the **order** (`write` then `flush`),
closing the auditor's named residual that a flush moved before the write would still pass.

Round-2 findings: **0 Critical, 0 High, 0 Medium, 1 Low** (M1, re-graded, with its
mitigation applied and the real fix deferred to a shared follow-up), plus the auditor's
concurrence on L3.

## Accepted Low, with rationale

- **L3 — 472-line test file.** The lane's declared write set is exactly one new test file;
  the length is dominated by six single-line golden constants and one shared fixture block,
  and moving the goldens away from the two assertions that pin them would weaken the very
  evidence they exist to provide. The auditor agreed the rule is an aim rather than a hard
  limit and that a useful split would require another file outside the write set.
- **M1 (as re-graded) — no cross-kind transaction.** Documented in code rather than fixed,
  because the fix belongs to `data/Daos.kt` + `AnnotationsRepository.kt` and should serve
  the backup collector too. Recommended follow-up: a `@Transaction` per-book annotations
  read exposed as a repository export snapshot, consumed by both this writer and
  `BackupCollector`.

## Test gate after the audit-driven changes

```
RUN-ANDROID-TESTS RESULT: SUCCEEDED
:app:testDebugUnitTest --tests '*ackup*' --tests '*nnotation*' --rerun-tasks
173 tests, 0 failures, 0 errors, 0 skipped  (15 of them this WI's)
:identity:test --tests '*BackupConformance*' --rerun-tasks — 12 tests, 0 failures
```

## Mutation pass (author-run, before the audit)

Five mutations applied to `AnnotationsExportWriter.kt` only, each reverted after its run;
all five killed:

| Mutation | Tests that went RED |
| --- | --- |
| emit `schemaVersion = 1` | 6, incl. the dedicated version test |
| hand-assemble the wire text, bypassing `mapper.json()` | 5 (both byte pins; the vector check did **not** catch it — key order is not part of that check) |
| escape every non-ASCII code point out of the payload | 1 — the CJK byte pin |
| `suggestedFileName` echoes the caller's string | 6 |
| ignore `bookKey`, export the whole library | 6 |

**VERDICT: follow-up-recommended** (zero Critical/High/Medium open; the one remaining Low
is documented in code and deferred to a named shared follow-up).
