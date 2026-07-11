---
branch: feat/132-wi6b-annotation-seams
threadId: 019f5050-5bb8-7d83-aa9b-7ef5fc2b1a2d
rounds: 1
final_verdict: ship-as-is
date: 2026-07-11
---

# Gate-4 audit — feature #132 WI-6b (annotation snapshot read + collector reads + restore seam)

Foundational DAO/repo seams the review sheet (WI-4) and annotation backup (WI-8) consume:
`AnnotationsSnapshot` + `RestoreAnnotationsReport`/`KindCounts` value types;
`AnnotationsRepository.annotationsForBook` (deterministic sorted highlights+notes one-shot);
`AnnotationDao.allNotes`/`allBookmarks` (collector reads) + `insertNoteIfAbsent`/
`insertBookmarkIfAbsent` + a `@Transaction restoreAnnotationEntities`; and the UUID-preserving
`AnnotationsRepository.restoreAnnotations(env, allowedBookKeys) -> RestoreAnnotationsReport`.

## Round 1 — Codex (gpt-5.6-sol, read-only sandbox)

Auditor confirmed every requested invariant:

- restore PRESERVES the backed-up UUID + createdAt/updatedAt (built via record/entity
  construction; the id-minting `addHighlight`/`addNote`/`addBookmark` create methods are NOT used).
- `OnConflictStrategy.IGNORE` = insert-if-absent; ignored rows counted `skipped` — a repeated
  restore applies 0 (idempotent).
- allowed-book scope exclusions counted `skipped`.
- locator parse-failure / bookKey-mismatch counted `failed` (never inserted).
- all inserts run inside ONE DAO `@Transaction`.
- `annotationsForBook` drops corrupt rows via `toRecordOrNull()` and sorts by `(createdAt, id)`.
- NO entity / DB-version / schema / migration change; NO `updateNote` added.

### Findings

- No Critical/High/Medium findings.
- **Low (non-blocking, accepted):** no explicit failure-injection test proving that an error in a
  later annotation kind rolls back earlier inserts. Rollback atomicity is structurally guaranteed
  by `@Transaction`; the restore does all validation/mapping BEFORE the transaction, so the DAO
  method only receives pre-validated entities (no per-row throw inside the transaction). Accepted —
  a fault-injection harness is out of scope for a foundational WI; the transaction boundary is
  the correctness guarantee.

**Verdict: ship-as-is.**

## Test gate

`RUN-ANDROID-TESTS RESULT: SUCCEEDED`
(`:app:testDebugUnitTest --tests '*RestoreAnnotations*' --tests '*AnnotationSnapshot*' --tests '*AnnotationsRepository*'`,
in-memory Room + Robolectric) — snapshot deterministic/sorted, corrupt row skipped, empty book empty,
restore preserves UUID+timestamps, repeated restore applies 0, non-allowed book skipped,
locator/bookKey mismatch + corrupt JSON counted failed, same-anchor different-UUID dedupes via the
(profileKey, anchorKey) unique index, per-kind counts exact.
