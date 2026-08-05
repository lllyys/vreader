---
branch: feat/165-wi-3-import-reader
threadId: 019fd2b1-0873-7993-b36e-b3669a8e650d
rounds: 3
final_verdict: ship-as-is
date: 2026-08-06
---

# Codex Audit Log — Feature #165 WI-3 (GH #2086)

`AnnotationsImportReader` + `AnnotationImportModels` — the untrusted-input
boundary of annotation import. A SAF-picked `annotations.json` arrives from
anywhere (rule 54), so this WI owns bounds, the per-row gate, the intra-file
collapse (§6.4 F-1…F-5), the already-present filter and the failure taxonomy.
The bounded SAF I/O itself is WI-4b; applying to Room is WI-4.

## Scope

Files audited (all new):

- `android/app/src/main/kotlin/com/vreader/app/annotations/AnnotationsImportReader.kt`
- `android/app/src/main/kotlin/com/vreader/app/annotations/AnnotationImportModels.kt`
- `android/app/src/test/kotlin/com/vreader/app/annotations/AnnotationsImportReaderTest.kt`
- `android/app/src/test/kotlin/com/vreader/app/annotations/AnnotationsImportReaderRowGateTest.kt`
- `android/app/src/test/kotlin/com/vreader/app/annotations/AnnotationsImportReaderCollapseTest.kt`
- `android/app/src/test/kotlin/com/vreader/app/annotations/AnnotationImportFixtures.kt`

Each round asked four questions specifically: (1) can any input throw, hang, or
allocate unboundedly; (2) can preview and apply diverge on any input; (3) is the
collapse genuinely deterministic from the bytes; (4) does any negative test pass
merely because the reader rejects everything.

Round transcripts: `.reports/audit-r1.txt`, `.reports/audit-r2.txt`,
`.reports/audit-r3.txt` (worktree-local, not committed).

## Round 1 — `019fd28d-e2f0-74c2-9f5f-8565ca844791`

2 High, 3 Medium, 1 Low. Every one was a real defect or a real overclaim.

| # | Severity | Finding | Resolution |
| --- | --- | --- | --- |
| R1-1 | High | **No liveness bound for a blocking or sparsely-progressing stream.** The zero-read guard counted only CONSECUTIVE zero returns, so a stream alternating 1 024 zero reads with one byte starves the loop forever without approaching the byte cap. The file also implied an unqualified "never hangs". | Budget made **cumulative** (`zeroReads` never reset). Header + `parse` KDoc now state termination precisely and delegate a never-returning `read` to WI-4b's `BoundedCallGate` by name. New test `streamThatStarvesTheZeroReadCounter_terminatesWithUnreadable` + `Fx.starvingStream()`. |
| R1-2 | High | **`Instant` → `toEpochMilli()` overflow is a genuine preview/apply divergence.** `Instant` spans years ±1e9; the Room columns are epoch millis and `restoreAnnotations` calls `toEpochMilli()` on every kept row, which throws `ArithmeticException` out of range. A row bearing `"+1000000000-12-31T23:59:59Z"` decoded cleanly, passed every gate, was **counted as importable**, and would then blow up the apply for the whole file — the user approves N and receives an error. | New `storableInstants(createdAt, updatedAt)` row gate for **all three kinds**. Test `anInstantThatCannotBecomeEpochMillis_isSkippedForEveryKind` (with a self-guard asserting the fixture instant really does overflow, so a JDK change cannot silently void the test) + discrimination partner `anOrdinaryPastTimestamp_isKept`. |
| R1-3 | Medium | "Never throws" was false: the catch sites take `Exception`, so a stream throwing an `Error` propagates. | Doc narrowed to malformed bytes + ordinary stream `Exception`s, stating `Error` propagation as deliberate. Not "fixed" by catching `Throwable` — that would be worse. |
| R1-4 | Medium | No test pinned the timestamp/apply requirement. | Covered by R1-2's tests. |
| R1-5 | Medium | **The whole row gate was exercised through highlights only**, so a mutation bypassing `validLocator` inside `keepNote`/`keepBookmark` would have survived. | New `theSharedIdentityAndLocatorGateAppliesToNotes` / `…ToBookmarks`, each driving all five gate limbs per kind against a surviving good sibling. |
| R1-6 | Low | The hang test used a returns-zero-forever stream, which a consecutive counter also catches. | Covered by R1-1's starvation test. |

Round 1 also **explicitly cleared**: allocation is bounded by the 2 MiB ceiling;
outer and inner JSON depth are scanned before any recursive decode; the UUID
regex has no catastrophic backtracking; the collapse matches Room's unique
indices kind by kind; determinism has no locale/clock/random/hash-iteration
dependence; the negative suite is not a blanket-rejection suite.

A defect the audit did not have to find, because the mutation pass found it
first: `runCatching` catches `Throwable`, so deleting the JSON depth guard was
**masked** by a swallowed `StackOverflowError` — every test stayed green. The
parse/decode sites were changed to `catch (e: Exception)`, which makes the guard
load-bearing; the mutation then fails with a real `StackOverflowError`.

## Round 2 — `019fd29c-9ac0-7c40-a7dd-14da87d85c80`

All six round-1 findings independently verified fixed. One new finding.

| # | Severity | Finding | Resolution |
| --- | --- | --- | --- |
| R2-1 | Medium | **UUID identity was case-sensitive during collapse.** Uppercase ids are accepted on purpose (Swift's `UUID.uuidString` is uppercase, so an iOS-written archive is all-uppercase) — but `Collapse.ids` compared verbatim, so one logical UUID spelled two ways survived both F-1 and F-2, and a differently-cased existing id slipped past the already-present filter. The cross-platform case this feature exists for is what made the hole reachable. | `Collapse.identityKey(id) = id.lowercase()` (the locale-**independent** overload) folds every comparison and every registration, including the `ExistingAnnotationState.ids` seeding. The **emitted row keeps its original wire spelling** — folding is for comparison only. Four new tests: within-kind (asserting the first wire spelling survives), across-kind, existing-state in either casing, and a discrimination partner proving distinct uppercase UUIDs still both import. |

Verdict: `follow-up-recommended`.

## Round 3 — `019fd2b1-0873-7993-b36e-b3669a8e650d`

Narrow adversarial re-audit of R2-1 plus a final sweep. Findings: **none**.

- Fix **complete**: every identity path folds through `identityKey`, including
  existing-state seeding and the single cross-kind set; no unfolded comparison
  or recording path exists downstream.
- Preserving the wire spelling while folding for comparison is **correct**.
  Asked specifically to argue the `file UPPERCASE X` vs `DB lowercase x` case
  from the identity contract rather than from what SQLite permits: dropping is
  right, because the contract treats them as one UUID and F-2 restores iOS's
  global UUID identity over Android's table-local, case-sensitive storage;
  importing it would create a logical duplicate and break idempotency.
  `preview 0 == applied 0` holds.
- `lowercase()` without a `Locale` is locale-independent, and `UUID_FORM`
  admits only ASCII hex and hyphens, so no case-folding hazard remains.
- The new section proves discrimination, not blanket collapse.

Verdict: **`ship-as-is`**. Zero open Critical/High/Medium.

Note recorded for honesty: round 3's sandbox could not start the test wrapper
(read-only FS), so its conclusion is code review only. The test evidence is the
lane's own runs, below.

## Test evidence

`RUN-ANDROID-TESTS RESULT: SUCCEEDED` — 81 tests / 0 failures for
`*AnnotationsImportReader*`, and 245 / 0 for the wider `*ackup*` + `*nnotation*`
sweep (29 classes, no pre-existing regression).

## Mutation pass

23 mutations applied and reverted one batch at a time; every one was killed by
its intended test, and each collapse rule's mutation left the other rules'
dedicated tests green. Full kill map in the WI's HANDOFF. Two mutations changed
the code rather than the test: the `Throwable`-swallowing parse sites (above)
and the cumulative zero-read budget.
