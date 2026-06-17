---
branch: feat/feature-106-wi3-room
threadId: 019ed8-wi3-room-3rounds
rounds: 3
final_verdict: ship-as-is
date: 2026-06-18
---

# Gate-4 audit — feature #106 WI-3 (Android Room persistence + VReaderLocator envelope)

WI-3 adds the Android persistence layer: a shared `:identity` `VReaderLocator`/
`Locator` envelope (engine-neutral value types), Room `BookEntity` +
`ReadingPositionEntity`, DAOs, `VReaderDatabase` (v2 + schema-versioned
`MIGRATION_1_2` scaffold + `exportSchema`), and `LibraryRepository` returning DTOs.
In-memory-Room CRUD + envelope round-trip tests + a migration round-trip test.

Codex (gpt-5.4, high), 3 rounds. The reading position stores the FULL
`VReaderLocator` envelope, not a bare `Locator` (Gate-2 Critical).

## Round 1 — 3 findings (block-recommended)

| file | sev | issue | resolution |
|---|---|---|---|
| Daos.kt | **Critical** | `BookDao.upsert` used `@Insert(REPLACE)`; in SQLite REPLACE = delete+insert, firing `reading_positions` `ON DELETE CASCADE` → a book re-import silently wipes its saved position. | Switched both DAOs to **`@Upsert`** (insert-or-UPDATE, no delete). Added regression `LibraryRepositoryTest.reUpsertBook_preservesSavedPosition`. |
| Locator.kt | **High** | Kotlin `Locator` didn't mirror Swift's validation contract — negative `page`/offset, one-sided/inverted ranges all serialized + could persist (violates `contracts/identity/locator.md`). | Added `validate()` (mirrors Swift `LocatorValidationError`), `validatedOrNull()`, `repairedForCanonicalization()` (nulls non-finite, iOS #109 parity). `savePosition` repairs non-finite + **throws** on structural invalidity. Tests: `savePosition_rejectsNegativePage`, `savePosition_rejectsInvertedRange`, `savePosition_repairsNonFiniteProgression`. |
| LibraryRepository.kt | **Medium** | Room flattened envelope fields into ad-hoc columns → a future `schemaVersion`-gated field would drop unless Room schema + mapper changed in lockstep (defeats "envelope evolves independently of Room"). | `ReadingPositionEntity` now stores the WHOLE envelope in a single `vreaderLocatorJSON` column (+ derived `canonicalHash`, `updatedAt`). `LibraryRepository` encodes/decodes the entire `VReaderLocator`; `DEFAULT_JSON` sets `ignoreUnknownKeys=true` (forward compat). Test: `loadPosition_toleratesForwardEnvelopeField`. |

## Round 2 — findings 1/2/3 confirmed resolved; 1 NEW High raised

| file | sev | issue | resolution |
|---|---|---|---|
| VReaderDatabase.kt | High | The Medium-fix rewrote `reading_positions` from the prior exported-v2 (flattened) layout to the new single-JSON layout while DB version stayed at 2 → "a database created by the earlier WI-3 build with the old v2 shape" would have no upgrade path. | **Withdrawn in round 3 — false-positive premise.** No such database exists in any committed/shipped lineage. |

## Round 3 — premise re-evaluated against verified git history (ship-as-is)

Presented the auditor with verified facts: `git log main -- android/app/schemas/`
is empty (no Room schema ever committed to main); main's `android/app/build.gradle.kts`
has no room/ksp deps (Room is introduced for the FIRST time in this unmerged WI-3);
the only shipped Android tags `android/v0.1.0` (WI-1 shell) and `android/v0.1.1`
(WI-2 identity module) carry no persistence; the old flattened-v2
`reading_positions` lived ONLY in this WI's uncommitted working tree.

Auditor verdict: **"The round-2 HIGH is withdrawn."** Shipping schema `version = 2`
with the new exported `2.json` is not a real upgrade-path defect — it is the
first-and-only on-device schema in vreader Android history. Bumping to v3 to model
the abandoned local shape would encode fictional release history. The only caveat
is procedural (a side-loaded uncommitted-dev APK's private DB is outside shipped
support scope) — not a merge blocker.

## Validation

- `scripts/run-android-tests.sh` (`:app:testDebugUnitTest`) → **RUN-ANDROID-TESTS
  RESULT: SUCCEEDED**; 17 data-layer tests (LibraryRepositoryTest 16 incl. the 5
  audit-driven additions, VReaderDatabaseMigrationTest 1), 0 failures.
- `contracts/conformance/run.sh kotlin` → **CONFORMANCE RESULT: PASS** (the
  `:identity` Locator additions are non-breaking; canonical JSON unchanged).
- Room `exportSchema` regenerated `2.json` to the single-`vreaderLocatorJSON`
  column set; the migration test's hand-built v1 matches it (migration round-trip
  green).

## Verdict

**ship-as-is.** All round-1 findings (Critical/High/Medium) resolved with tests;
the round-2 High withdrawn on verified never-shipped state. Zero open
Critical/High/Medium after 3 rounds.
