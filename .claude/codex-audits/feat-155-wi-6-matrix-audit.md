---
branch: feat/155-wi-6-matrix
threadId: see .reports/audit-r1.txt / audit-r2.txt / audit-r3.txt (run-codex.sh, rule 53)
rounds: 3
final_verdict: block-recommended
date: 2026-08-05
---

# Codex Audit Log — feature #155 WI-6 (Gate-5 acceptance matrix)

Work item: the real-book format matrix + the Gate-5 acceptance run for VReader's exported
inbound-document entry point.

Write-set (binding, ONE file):
`android/app/src/androidTest/kotlin/com/vreader/app/imports/IncomingIntentFormatMatrixConnectedTest.kt`.
The evidence file (`dev-docs/verification/feature-155-*.md`) is orchestrator-owned under rule 55, so
"the verification evidence is not committed yet" is by design, not an omission of this lane.

The central question put to the auditor every round: **can any test in this matrix pass WITHOUT
actually importing the format it names?**

## Round 1 — 10 findings (3 High, 4 Medium, 3 Low). All fixed.

| # | Sev | Finding | Resolution |
|---|---|---|---|
| 1 | High | Imported bytes were never bound to the named fixture — only format + byte COUNT were asserted, so any same-length payload passed. | The test now hashes the SOURCE file with its own `MessageDigest`, composes the expected key via `Identity.canonicalKey`, and `assertImported` pins exact key + `contentSHA256` + byte count + exact staged `sourceUri` + **the SHA-256 of the stored artifact**. |
| 2 | High | "A new row appeared" attributed any row to this intent; a previous test's still-queued import could satisfy it. | `awaitBook` waits for THIS document's exact identity; provenance is asserted against the exact staged URI. |
| 3 | High | The plan's §8.5 duplicate-identity case (SAF-import, then Open-with the same bytes) was missing. | Added `aBookAlreadyImportedThroughTheSafPathIsNotDuplicatedByAnOpenWith`: same key, no second row, no second artifact, unchanged stored bytes. |
| 4 | Med | MD fixture substitutable. | Section anchors added; the guarantee's scope corrected (see round 2/3). |
| 5 | Med | A stale `cacheDir` copy could stand in for the committed PDF asset. | `assetFile` rewrites from the packaged asset on every call. |
| 6 | Med | The partial batch's negative assertion used a fixed 2 s settle. | Sleep removed. The coordinator drains ONE FIFO queue with ONE worker in input order, so the THIRD item's row existing proves the second was already processed — an ordering proof, not a delay. **The auditor independently re-derived and confirmed this against `ImportActivity`/`IncomingImportCoordinator` in rounds 2 and 3, including the inline depth-overflow path.** |
| 7 | Med | Teardown deleted every post-baseline row and swallowed failures. | Rewritten (see rounds 2/3). |
| 8-10 | Low | Cache fixtures never removed; "byte-for-byte" claimed from a length check; correlated assertions. | Temp files tracked + deleted; artifact digest replaces the length check; independent expectations added. |

## Round 2 — 0 High. 2 Medium + 1 Low. All fixed.

| # | Sev | Finding | Resolution |
|---|---|---|---|
| A | Med | MD: "a substituted document cannot pass BOTH" is FALSE — the digest assertions only prove the pushed bytes travelled intact. | Content anchors added (`## System Diagram`, `## Layers`, `## File Organization`), and the claim rewritten to its true scope: the checks reject an absent push and a hand-written stub but do **not** cryptographically bind the bytes to the worktree copy; a pinned digest would break the test on every unrelated docs commit, and passing the digest in at push time is a **named harness follow-up**. |
| B | Med | Teardown could abort early, treated `resolver.delete() == 0` as success, and could delete a pre-existing row (identities are deterministic). | Each step individually wrapped with failures accumulated; bookkeeping cleared in `finally`; `delete <= 0` recorded as a failure; ownership established at registration time. |
| C | Low | `awaitBook` accepted any format's key for those bytes, so a pre-existing row under another format could be returned before the real import landed. | `awaitBook(staged, format)` now requires the exact key **and** the exact staged URI; every call site passes its expected format. |

Round 2 explicitly confirmed: the duplicate test's completion signal is sound
(`Daos.upsertPreservingAuthor` synchronously rewrites `sourceUri` on the conflict branch); no
Kotlin/API-level issues (`BookFormat.entries`, `MessageDigest`, API-Q MediaStore, asset access); and
the `setPackage` documentation is honest about exercising post-chooser filter routing rather than a
bare implicit chooser launch.

## Round 3 (cap) — verdict `block-recommended`, 3 Medium. Fixes APPLIED, NOT re-audited.

| # | Sev | Finding | Fix applied (the auditor's own prescription) |
|---|---|---|---|
| I | Med | The MD **test's** KDoc still carried the round-2 sentence "a substituted document cannot pass BOTH" — the round-2 edit corrected the class KDoc and the enum but missed this one, so the file contradicted itself. | Sentence replaced with the scoped statement; the file no longer overstates the guarantee anywhere. |
| II | Med | `finishAll` was inside the `try` but not individually wrapped: a throw there jumped to `finally`, clearing the bookkeeping and skipping row / MediaStore / temp-file cleanup. | Both calls individually `runCatching`-wrapped, failures appended to `leaked`, cleanup continues. |
| III | Med | Excluding a pre-existing key from deletion was not enough: the import under test REWRITES that row's import-owned columns, so teardown would leave a stranger's row mutated and pointing at a URI about to be deleted. | `registerKey` now **refuses to run** — a loud `AssertionError` naming the key, the title and `adb shell pm clear com.vreader.app` — before anything is dispatched. Auditor-offered alternative (snapshot + faithful restore) rejected: no repository API restores a row faithfully, and a dirty device invalidates the matrix's premise anyway. |

**Status of these three fixes: applied and green, but NOT re-audited — round 3 is the rule-53 /
rule-55 cap, and certifying my own fix to an auditor's finding is forbidden.** The lane therefore
returns `blocked`, with the code in its best state and the decision (accept, or spend a fourth
round) left to the orchestrator. Fix III was itself caught by the test suite rather than by
inspection: it initially failed `aBookAlreadyImportedThroughTheSafPath…`, because that test
registers its key and then re-registered it through `stage`; the second registration now passes
`format = null` with the reason stated at the call site.

## Test gate after the round-3 fixes

`RUN-ANDROID-TESTS RESULT: SUCCEEDED` — `IncomingIntentFormatMatrixConnectedTest` **12/12**, AVD
`vreader-test` (API 35), fixtures re-pushed for the run (the connected task wipes
`/sdcard/Android/data/com.vreader.app/` at run end — confirmed empirically this session).

Also re-run this session, per the WI's "connected tests merged during earlier WIs are UNVERIFIED
until they run" clause (the #133 recurrence): `IncomingIntentImportConnectedTest` **11/11** and
`ImportFilterResolutionConnectedTest` **17/17** — both green on the first real execution, so no
#133-style RED-when-run appeared. 40 connected tests, 0 failures.

## Follow-ups named, not fixed here (outside this file's write-set)

1. **Harness-supplied fixture digests** — the runner could pass each pushed fixture's SHA-256 to the
   test so a living document (`docs/architecture.md`) could be bound cryptographically rather than
   by size + title + anchors.
2. The zero-byte case documents, without endorsing, that a zero-byte payload becomes a zero-byte
   library row: the import layer is content-agnostic by design. Whether the library should refuse
   an empty "book" is a product decision for a tracker row, not this WI.
