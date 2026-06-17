---
branch: feat/feature-109-wi1-nfc-migration
threadId: 019ed616-c1be-7c31-8d52-c89c1bf973f3
rounds: 3
final_verdict: ship-as-is
date: 2026-06-17
---

# Gate-4 audit — feature #109 WI-1 (NFC canonical-locator recompute backfill)

Independent Codex audit (gpt-5.4, high reasoning, read-only sandbox) of the WI-1
diff: NFC normalization of `Locator.canonicalJSON` string fields + the one-shot
recompute of the 18 persisted derived-key sites + non-finite repair.

Codex threadIds: round 1 `019ed616-c1be-7c31-8d52-c89c1bf973f3`, round 2
`019ed62c-a9b2-7af3-9a4b-acc06cf26cd0`. Round 3 fell back to a manual mini-audit
(Codex quota exhausted — see round 3).

## Round 1 (Codex) — design: SchemaV9→V10 custom migration stage

| file:line | severity | issue | resolution |
|---|---|---|---|
| V9toV10Migration.swift:27 | Medium | `didMigrate` loaded every row into one context, one save — not memory-bounded for large libraries. | Acting on this + M2 led to the pivot (below). Superseded. |
| SchemaV10MigrationTests.swift:105 | Medium | Disk test seeded rows with already-V10-style keys; proved reopen/idempotency but not the core rewrite or non-finite repair. | Strengthened the test to seed a PERSISTED non-finite locator + assert post-migration repair. **This exposed a deeper defect — see below.** |
| docs/architecture.md:12 | Low | Stale: doc said SchemaV9 / data layer claims out of date. | Fixed (App Layer + Data Layer notes updated). |

Codex confirmed the production logic correct: `precomposedStringWithCanonicalMapping`
is the right Swift NFC match for Kotlin `Normalizer.normalize(_, NFC)`; preserves
NFC/NFD twins + canonical singletons without NFKC-folding compatibility chars;
`repairedForCanonicalization()` nulls only non-finite progression while preserving
the rest; `recomputeKey()` re-derives keys correctly; no Swift-6 actor-isolation
problem.

### Pivot (between round 1 and round 2): migration stage → launch backfill

Acting on round-1 M2, the strengthened disk test (seed a persisted non-finite
locator) proved the `MigrationStage.custom` **never fires**: SchemaV10 was
model-set-identical to V9, and SwiftData keys migration on entity-shape hashes —
it cannot distinguish two schema-identical versions, so the custom stage is
skipped (the non-finite repair never ran on reopen). This is a fundamental
SwiftData limitation for pure (no-shape-change) data transforms.

**Resolution**: dropped `SchemaV10` + `V9toV10Migration`; V9 stays the head
schema with empty stages. The recompute now ships as `LocatorKeyBackfillMigration`
— a synchronous, UserDefaults-gated, idempotent one-shot launch backfill invoked
from `VReaderApp.init()` before any store consumer is constructed (mirrors the
`ReadingModeMigration` precedent's race-free synchronous-launch rationale).
Recorded in the plan revision history (v4).

## Round 2 (Codex) — design: launch backfill

| file:line | severity | issue | resolution |
|---|---|---|---|
| VReaderApp.swift:145 / TestSeeder | Medium (M3) | Gate flag in global `UserDefaults.standard` could be set by an ephemeral in-memory UI-test launch (in-memory store, but defaults persist) → starve a later real on-disk backfill. | `VReaderApp.init()` now computes `isInMemoryStore` and SKIPS the backfill for in-memory stores; release always disk → always runs. |
| LocatorKeyBackfillMigration.swift:59,80 | Medium (M4) | Offset paging by non-unique `createdAt`/`updatedAt` is not skip-safe (UUIDs aren't `Comparable` for a tiebreaker) — ties spanning a page boundary could skip/reprocess rows. | Dropped offset paging; each entity type is now ONE fetch + ONE save (a stable snapshot — skip-safe by construction). Memory is safe because the backfill runs AFTER store-open (no store-open-blocking risk) and the corpus is domain-bounded. |
| LocatorKeyBackfillMigrationTests.swift:27,94 | Low (L2) | Replacement tests all in-memory + called `run` directly; no persisted launch-on-reopen coverage. | Added `backfillOverPersistedStoreAcrossRelaunch` — disk-backed, 3 simulated launches (seed → backfill repairs persisted non-finite + NFD rows → gate makes the 3rd a no-op). |

Round 2 confirmed round-1 M1 materially improved and L1 resolved.

## Round 3 (manual fallback — Codex quota exhausted)

Codex returned `ERROR: You've hit your usage limit … try again at Jun 18th
11:38 AM` for the round-3 re-audit (session `019ed634-a0c8-7061-86f5-384078051cce`
never produced findings). Per `.claude/rules/53-codex-runner-isolation.md` +
rule 47's manual-fallback provision, the round-3 verification of the M3/M4/L2
fixes is a manual mini-audit.

### Manual Audit Evidence

**Files read**: `vreader/Models/Migration/LocatorKeyBackfillMigration.swift`,
`vreader/App/VReaderApp.swift` (lines 84–146), `vreader/Models/Locator.swift`,
`vreader/Models/{Highlight,Bookmark,AnnotationNote,ReadingPosition}.swift`,
`vreaderTests/Models/Migration/LocatorKeyBackfillMigrationTests.swift`.

**M3 resolved** — `isInMemoryStore` is assigned on every code path: DEBUG
UI-testing → `!needsDiskBackedStore`; DEBUG non-UI-testing → `false`; release
(`#else`) → `false`. The backfill is guarded `if !isInMemoryStore`, so an
in-memory launch never calls `run()` and never writes the `.standard` flag.
Release always uses a disk store → always runs. Correct for all paths.

**M4 resolved** — `recomputeAll` does a single `context.fetch(FetchDescriptor<T>())`
(no `fetchLimit`/`fetchOffset`), iterates the whole snapshot, saves once. One
fetch is a consistent snapshot → every row visited exactly once, no tie-induced
skip/reprocess. Verified empirically: the disk relaunch test repairs the
persisted non-finite row across a fresh-container reopen (a genuine stored-value
change), which the prior migration-stage design failed to do.

**Edge cases checked**: empty store (guard `!rows.isEmpty` → no-op + flag set);
non-finite repair (asserted in-memory + disk); NFD/NFC twins (value-level +
preserved-verbatim on disk); gate set/unset on success/throw; idempotency
(second run no-op); partial-progress safety (per-type save + `recomputeKey`
idempotent → a throw mid-run leaves the flag unset and re-runs harmlessly).

**Risks accepted**: single-fetch loads one entity type's full row set into the
context at once — bounded by a personal reader's annotation corpus and run
post-store-open (non-blocking), so acceptable; offset paging was rejected as
unsafe on non-unique sort keys.

**Tests**: `LocatorKeyBackfillMigrationTests` (6 tests: plan-state, value-level
repair/recompute, populated-store backfill, gate-gating, disk relaunch,
idempotency) + `LocatorCanonicalHashTests` NFC additions + `IdentityConformanceTests`
(shared NFD vector) all green via `scripts/run-tests.sh`.

**No new Critical/High/Medium introduced.**

## Verdict

**ship-as-is.** Round-1 + round-2 Codex findings all resolved (the round-1 Medium
that surfaced the migration-stage defect drove a sound pivot to a launch
backfill). Round-3 manual fallback confirms M3/M4/L2 closed with no new
Critical/High/Medium. Coverage spans in-memory + disk-backed relaunch.
