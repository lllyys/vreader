---
branch: worktree-agent-a2bb298c1bb3dfc22
threadId: 019fd596-531b-7362-8632-e6087e662f5e
rounds: 2
final_verdict: ship-as-is
date: 2026-08-06
---

# Gate-4 audit — feature #152 WI-1 (StorageNaming extraction + CoverPaths)

Auditor: Codex `gpt-5.5`, reasoning effort `high`, read-only sandbox, driven through
`scripts/run-codex.sh` (rule 53). Author/auditor separation preserved — the auditor is a separate
process with no access to this session's reasoning.

- Round 1 thread: `019fd582-1584-7853-90be-f3165c2a7fb4` → `follow-up-recommended`
- Round 2 thread: `019fd596-531b-7362-8632-e6087e662f5e` → `ship-as-is`

Full transcripts: `.reports/audit-r1.txt`, `.reports/audit-r2.txt` (worktree-local, not committed).

## Scope

| File | Change |
|---|---|
| `android/app/src/main/kotlin/com/vreader/app/data/StorageNaming.kt` | new |
| `android/app/src/main/kotlin/com/vreader/app/data/BookImporter.kt` | delegate only |
| `android/app/src/main/kotlin/com/vreader/app/library/covers/CoverPaths.kt` | new |
| `android/app/src/test/kotlin/com/vreader/app/data/StorageNamingTest.kt` | new |
| `android/app/src/test/kotlin/com/vreader/app/library/covers/CoverPathsTest.kt` | new |

## Round 1 — `follow-up-recommended`

Zero Critical / High / Medium. Two Low, **both fixed** (not accepted, not deferred).

| # | Severity | Finding | Disposition |
|---|---|---|---|
| L-1 | Low | The injectivity argument is stated over `Identity.canonicalKey`'s image, but `CoverPaths` enforced the wider `parseCanonicalKey(key) != null`. `parseCanonicalKey` reads its byte count with `toLongOrNull`, which also accepts `+4096`, `04096`, `-0` — spellings the emitter never produces. No collision and no production ingress, but the enforced domain was wider than the proven one. | **FIXED**, taking the auditor's first option. `CoverPaths.isCanonical` now round-trips: `key == Identity.canonicalKey(parsed.format.name, parsed.contentSHA256, parsed.fileByteCount)`. Two tests added: `coverPaths_rejectsNonEmittedByteCountSpellings` (the four near-miss spellings) and `coverPaths_acceptsEveryEmittedCanonicalKey` (the tightening must not over-reject). Mutation M9 confirms the tightening is itself covered. |
| L-2 | Low | `StorageNamingTest.kt` contained a literal NUL byte in an invalid-key fixture. It compiled and passed, but made the file binary to git, editors and scanners. | **FIXED.** Confirmed real, not a false positive: `wc -c` and `tr -d '\000' \| wc -c` differed by exactly 1, and `file(1)` reported `data`. Root cause was an authoring artifact — a control character emitted where a trailing space was intended. All whitespace/control fixtures are now built by concatenation (`+ ' '`, `+ '\t'`, `+ Char(0)`, `+ '\n'`) rather than written as literals, which also **widened** the case list from one accidental NUL to four deliberate control characters. `file(1)` now reports UTF-8 text on both test sources and all three main sources. |

## Round 2 — `ship-as-is`

Zero findings at every severity. The auditor independently re-verified, rather than
rubber-stamping:

- **The tightening does not over-reject.** Production keys from
  `DocumentFingerprint.Result.canonicalKey(BookFormat)` are accepted for all five enum formats,
  lowercase SHA-256, byte count `0`, `Long.MAX_VALUE`, and arbitrary non-negative `Long`.
- **The extraction is behaviour-preserving.** The pre-extraction private method and
  `StorageNaming.fileNameForKey` use the same regex and the same replacement; hoisting the `Regex`
  to a `val` is a per-call-allocation change only.
- **The control-character fix is clean.** Byte count unchanged after `tr -d '\000'`.

Explicitly noted by the auditor: the round-2 sandbox is read-only, so it performed a static/diff
audit plus byte scans and did **not** run Gradle. The test evidence below is this lane's.

## Findings confirmed, not merely unraised (recorded so a later round does not re-derive them)

- **The M-9 disposition holds.** `a:b` and `a/b` really do both map to `a_b`; the collision is
  unreachable because a canonical key contains no `_` and exactly two `:`, so `:`→`_` is
  **invertible** there. The tests assert the inverse directly, which is a constructive proof rather
  than sampled distinctness.
- **No real path can reach the `require` with a non-canonical key.** The auditor grepped every
  writer of `BookEntity.fingerprintKey`: production writes converge on `BookImporter`, whose key is
  always `DocumentFingerprint.Result.canonicalKey(...)`; restore verifies `expectedKey` **before**
  any artifact promotion or DB write; `LibraryRepository.upsertBook` (the only whole-row writer)
  has no production caller. Test fixtures write non-canonical keys, but tests are not a production
  path. So the `require` is a programmer-error assertion, not a user-reachable failure mode — which
  is what the brief asked be adjudicated before shipping it.
- **`BookImporter`'s observable behaviour is unchanged**, including which exceptions it can throw:
  `StorageNaming.fileNameForKey` is deliberately left **total** (no `require`), so the precondition
  lives only in `CoverPaths`, the type that composes a filesystem path from an untyped String.
- **Rule 22 is satisfied without touching an out-of-write-set file.** `BookFileProvider.kt:4`
  references `BookImporter.fileNameForKey`; keeping the method as a one-line delegator (rather than
  inlining the call) leaves that comment accurate.

## Mutation testing (the evidence the tests bite)

Nine mutations, each run through `scripts/run-android-tests.sh` and then reverted. **Eight killed,
one survived and is an equivalent mutant — reported, not papered over.**

| # | Mutation | Result |
|---|---|---|
| M1 | `StorageNaming` substitution `"_"` → `"-"` | **KILLED** — 5 tests, incl. the golden case and the real-import equality |
| M2 | `CoverPaths` precondition removed entirely | **KILLED** — `coverPaths_rejectsNonCanonicalKeys`, `everyEntryPointRejectsANonCanonicalKey` (re-run as M2b after the L-1 fix: also `coverPaths_rejectsNonEmittedByteCountSpellings`) |
| M3 | `CoverPaths.remove` becomes a no-op | **KILLED** — 4 tests |
| M4 | `hasCover` uses `exists()` instead of `isFile` | **KILLED** — `hasCover_isFalseWhenThePathIsADirectory`. Confirms the `isFile` guard is load-bearing: a directory reports non-zero `length()` on this filesystem |
| M5 | `hasCover` drops the `length() > 0` guard | **KILLED** — `hasCover_isFalseForAZeroLengthFile` |
| M6 | `hasCover` composes its own path, bypassing `coverFile`'s check | **KILLED** — `everyEntryPointRejectsANonCanonicalKey`. This is why the precondition is asserted per entry point rather than assumed from delegation |
| M7a | `BookImporter` keeps its own copy, differing only by dropping `-` from the safe class | **SURVIVED — equivalent mutant.** No canonical key contains `-`, so the two mappings agree on the entire contract domain. Unkillable by construction, and harmless for the same reason. Recorded because a surviving mutation is a finding, not a formality |
| M7b | `BookImporter` keeps its own copy with an *observable* drift (`"-"` replacement) | **KILLED** — `bookImporter_namesItsArtifactWith_storageNaming`, which is exactly that test's purpose |
| M8 | `StorageNaming` stops sanitising `:` | **KILLED** — 6 tests across both suites |
| M9 | `isCanonical` reverted to the loose `parseCanonicalKey != null` (i.e. undo the L-1 fix) | **KILLED** — `coverPaths_rejectsNonEmittedByteCountSpellings` |

Note on M7a: the structural guarantee that the two stores cannot drift comes from there being **one
function**, not from a test. No test can distinguish "one function" from "two byte-identical
copies"; M7b shows the test catches drift the moment it becomes observable.

## Test evidence

```
RUN-ANDROID-TESTS RESULT: SUCCEEDED
```

Full JVM suite (`ANDROID_CMD="cd android && ./gradlew :app:testDebugUnitTest --rerun-tasks"`):
**192 classes, 2621 tests, 0 skipped, 0 failures, 0 errors.**

Zero skips is asserted, not assumed — a skip exits 0 exactly like a pass (bug #369). New coverage:
`StorageNamingTest` 12 tests, `CoverPathsTest` 12 tests.

Bug #374 (`VLogTest` order-dependent flake) did **not** manifest: `VLogTest` ran 17/17 clean inside
the full suite on every one of the three full-suite runs in this lane.
