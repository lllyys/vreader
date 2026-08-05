---
branch: feat/155-wi-1-importer-format
threadId: 019fcf37-ec09-7892-9b80-b53b6fd39d5a
rounds: 1
final_verdict: ship-as-is
date: 2026-08-05
---

# Gate 4 — implementation audit: feature #155 WI-1 (`BookImporter` format override)

Independent audit via `scripts/run-codex.sh` (rule 53 — never bare `codex exec`).
Model `gpt-5.6-sol`, `sandbox: read-only`, `approval: never`. Raw transcript:
`.reports/audit-r1.txt` (worktree-local, not committed).

**Commit audited**: `7962bbfa` — the only commit on the branch.

**Scope** (the WI's entire write-set, two files):

- `android/app/src/main/kotlin/com/vreader/app/data/BookImporter.kt`
- `android/app/src/test/kotlin/com/vreader/app/data/BookImporterTest.kt`

## Round 1

Prompt asked for six things explicitly: (1) null-behaviour equivalence read
across the **whole** method rather than the diff hunk, (2) the identity contract
— whether the explicit-format and extension-derived paths could ever yield
different canonical keys for the same bytes, *and* whether the test genuinely
proves it or merely appears to, (3) call-site completeness re-grepped
independently, (4) test quality incl. tests that could pass while the code is
wrong, (5) Kotlin shadowing/nullability/coroutine correctness, (6) whether the
API shape burdens WI-3 / WI-5.

### Findings

| Severity | Count |
| --- | --- |
| CRITICAL | None |
| HIGH | None |
| MEDIUM | None |
| LOW | None |

### Auditor's substantive notes

- Null behaviour is semantically unchanged: the filename lookup and the
  `UnsupportedFormat(displayName)` path remain intact.
- A non-null override bypasses filename resolution and consistently drives both
  canonical identity and `originalFormat`.
- Both paths use the same `BookFormat` enum value and
  `Identity.canonicalKey(format.name, sha256, byteCount)`, so identical bytes +
  identical logical format **cannot** diverge in identity.
- The identity regression test genuinely compares the untouched
  extension-derived path against the explicit-format path (rather than
  rebuilding the expectation with the implementation's own helper) and verifies
  a single persisted row.
- All three production callers remain unchanged and compile-compatible because
  the parameter is trailing and defaulted; every unit/instrumentation caller
  found by an independent search is likewise compatible.
- The six added cases meaningfully cover null behaviour, unknown / conflicting /
  extensionless names, identity dedup, CJK, and the `expectedKey` interaction.
  Pre-existing tests were appended to, never modified; empty-stream coverage
  already existed.
- Per-`BookFormat` enumeration would add little value — the implementation
  passes the enum through with no format-specific branching.
- `resolvedFormat` correctly avoids shadowing the parameter inside the
  `input.use` lambda and is non-null after the Elvis chain. No coroutine,
  stream-ownership, or nullability regression found.
- The API suits WI-3 / WI-5: the resolver can pass a named `format` with no
  further signature change.

### Verdict

`VERDICT: ship-as-is` — no fixes applied, so no re-test was required (the
targeted and full gates below were already green at the audited commit).

## Test evidence at the audited commit

Counts read from the JUnit XML under
`android/app/build/test-results/testDebugUnitTest/`, not from `BUILD SUCCESSFUL`
(a suite that runs 0 tests also prints `BUILD SUCCESSFUL`).

| Gate | Command | Result |
| --- | --- | --- |
| Targeted | `ANDROID_CMD="cd android && ./gradlew :app:testDebugUnitTest --tests '*BookImporterTest*' --rerun-tasks" scripts/run-android-tests.sh` | `RUN-ANDROID-TESTS RESULT: SUCCEEDED` — 17 tests / 0 failures / 0 errors / 0 skipped (11 pre-existing + 6 new) |
| Wider | `ANDROID_CMD="cd android && ./gradlew :app:testDebugUnitTest --rerun-tasks" scripts/run-android-tests.sh` | `RUN-ANDROID-TESTS RESULT: SUCCEEDED` — 1786 tests / 0 failures / 0 errors across 158 classes |

RED was demonstrated before the implementation: the same targeted gate failed at
`:app:compileDebugUnitTestKotlin` with eight instances of
`No parameter with name 'format' found.` — the API did not exist, so none of the
six new cases could have been green beforehand.
