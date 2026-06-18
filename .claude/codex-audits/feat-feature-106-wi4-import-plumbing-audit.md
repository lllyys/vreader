---
branch: feat/feature-106-wi4-import-plumbing
threadId: 019ed9-wi4-import-3rounds
rounds: 3
final_verdict: ship-as-is
date: 2026-06-18
---

# Gate-4 audit — feature #106 WI-4 (Android EPUB import PLUMBING)

WI-4 ships the UI-free import plumbing (the Library list + SAF-launch UI is
design-blocked, #1744, per the user's rule-51 decision): `DocumentFingerprint`
(streaming SHA-256 + byte count + format detection, `:identity`) and
`BookImporter` (copy SAF stream → app-private storage → fingerprint the LOCAL
artifact → store `BookEntity`, source URI as metadata — Gate-2 High-2).

Codex (gpt-5.4, high), 3 rounds.

## Round 1 — 1 High, 2 Medium, 1 Low (block-recommended)

| file | sev | issue | resolution |
|---|---|---|---|
| BookImporter.kt | **High** | Final-artifact promotion not failure-safe: deleted `finalFile` before replace; the `renameTo` fallback copied directly into the live path → interruption/race could leave it missing/partial (breaks Gate-2 High-2 on the fallback). | `promoteAtomically()` — `Files.move(ATOMIC_MOVE, REPLACE_EXISTING)`, falling back to same-dir `Files.move(REPLACE_EXISTING)` (still a single rename). Never delete-then-copy into the live path. |
| BookImporter.kt | **Medium** | Caller-provided `InputStream` leaked on early-error paths (unsupported format / temp-create failure before hashing closed it). | Whole body wrapped in `input.use { }`; `DocumentFingerprint.hashing` no longer closes caller-owned streams (consistent ownership). |
| BookImporter.kt | **Medium** | Suspend API ran blocking IO + hashing on the caller's dispatcher (UI ANR risk). | Injected `ioDispatcher: CoroutineDispatcher = Dispatchers.IO`; body in `withContext(ioDispatcher)`. |
| BookImporterTest.kt | Low | Missing edge tests (empty stream, mid-copy failure cleanup, concurrent same-key). | Added `import_emptyStream_…`, `import_midCopyFailure_leavesNoArtifact`, `import_concurrentSameKey_…`. |

## Round 2 — R1 findings confirmed resolved; 1 Medium + 1 Low new (follow-up-recommended)

| file | sev | issue | resolution |
|---|---|---|---|
| BookImporter.kt | Medium | If `repository.upsertBook` failed AFTER promotion, the promoted artifact was orphaned in `booksDir`. | Wrapped the upsert in try/catch → delete the promoted file on failure before rethrowing. (Refined in round 3.) |
| BookImporterTest.kt | Low | The concurrent test used `Dispatchers.Unconfined` (inline) → could false-green on the race. | Rewrote with a REAL `Dispatchers.IO` + a `CyclicBarrier(2)` rendezvous mid-copy so the two promotions genuinely overlap. |

## Round 3 — the round-2 rollback regressed re-import; fixed (block → ship-as-is)

| file | sev | issue | resolution |
|---|---|---|---|
| BookImporter.kt | Medium | The round-2 rollback `finalFile.delete()` was unsafe on **re-import**: `promoteAtomically` replaces the live artifact first, so a DB failure on a re-import would delete the only on-disk copy while the existing `books` row still referenced it → broken entry. | Capture `artifactPreexisted = finalFile.exists()` BEFORE promotion; on DB failure delete ONLY if `!artifactPreexisted` (a true fresh-import orphan). A pre-existing artifact is byte-identical (same key ⇒ same content) and still validly referenced, so it is kept. New test `reimport_dbWriteFailure_preservesExistingArtifact`. |

This was a regression I introduced in the round-2 fix, caught by the auditor and
corrected with the `artifactPreexisted` guard. The targeted regression test
directly verifies the re-import case (existing artifact survives + still resolves
to its key). At the rule-47 3-round audit cap, this final fix was closed via the
regression test rather than a 4th open-ended audit round — the finding was
concrete and convergent (4 → 2 → 1), not a thrash.

## Validation

- `scripts/run-android-tests.sh :app:testDebugUnitTest` → **SUCCEEDED**;
  `BookImporterTest` 10 tests, 0 failures (happy-path + cold-restart identity +
  idempotency/position-preservation + unsupported-format + CJK + empty stream +
  mid-copy-failure cleanup + concurrent-same-key (real `Dispatchers.IO` + barrier)
  + fresh-import-DB-failure rollback + re-import-DB-failure preservation).
- `contracts/conformance/run.sh kotlin` → **PASS** (the `DocumentFingerprint`
  ownership change doesn't touch the asserted canonical contracts).

## Verdict

**ship-as-is.** All round-1 findings (High + 2 Medium) resolved; the round-2
Medium/Low and the round-3 re-import regression fixed with targeted tests. Zero
open Critical/High/Medium at the 3-round cap.
