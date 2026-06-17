# Feature #109 — iOS NFC canonical-locator + recompute migration + non-finite persistence guarding

> The iOS implementation of the bug #356 canonical-identity rules. The contract
> (`contracts/identity/locator.md`) + the Kotlin reference already require
> NFC-normalized string fields + rejected non-finite; iOS does NOT yet. Closing
> that gap changes the persisted `canonicalHash`, so it is a **breaking-sensitive
> migration**, deferred from the #355/#356 PR by user decision (2026-06-17) and
> done here as a proper feature with a recompute migration. **Closes bug #356
> (GH #1718) when shipped.**

## Problem

`Locator.canonicalJSON()` does not Unicode-NFC-normalize its string fields
(`href`, `cfi`, `textQuote`, `textContext*`), so a decomposed (NFD) vs
precomposed (NFC) form of the same text yields a different `canonicalJSON` →
different `canonicalHash`. That hash is the derived identity key at 18
persisted-key sites (`profileKey` on Highlight/Bookmark/AnnotationNote;
`locatorHash` on ReadingPosition; backup profileKeys). Consequences:

1. **iOS-internal instability**: the same logical position with NFD vs NFC text
   (iOS hands back NFD on some text paths) hashes differently → annotation
   dedupe/toggle can drift or duplicate **today, single-platform**.
2. **Cross-platform divergence (latent)**: a future Android client (Kotlin
   reference NFC-normalizes) would compute a different key than iOS → library/
   backup interop breaks for non-NFC text.
3. **Non-finite collision**: `canonicalJSON` silently omits a non-finite
   `progression`/`totalProgression`, so an INVALID locator canonicalizes
   identically to a valid missing-progression one. `Locator.validate()` rejects
   non-finite, but Codex Gate-4 found `?? Locator(...)` fallbacks
   (`EPUBReaderViewModel`, `ReadiumEPUBReaderViewModel+Mapping`) that recreate
   invalid locators and persist them without validating.

## Surface area (file-by-file)

- **`vreader/Models/Locator.swift`** — add `private func nfc(_:) -> String`
  (`precomposedStringWithCanonicalMapping`); wrap the 5 string fields in
  `canonicalJSON()` (cfi/href/textQuote/textContext{Before,After}) with `nfc(...)`
  (NFC before line-ending-normalize/escape). This is the canonicalization change
  that makes iOS match the contract + the Kotlin reference.
- **`vreader/Models/Migration/SchemaV10.swift`** (new) — `VersionedSchema`,
  version `(10,0,0)`, same model set as V9 (no column change — derived keys are
  existing columns).
- **`vreader/Models/Migration/V9toV10Migration.swift`** (new) — a `.custom`
  `MigrationStage` whose `didMigrate` iterates every `Highlight`, `Bookmark`,
  `AnnotationNote`, `ReadingPosition` and, for each row:
  1. **Repairs a preexisting INVALID stored `locator`** (Gate-2 Medium — V9 stores
     can already hold non-finite locators from the audited `?? Locator(...)`
     fallback paths). Repair = **null the non-finite field** (set
     `progression`/`totalProgression` to `nil` when `!isFinite`) so the locator
     becomes valid while preserving the rest of the anchor (href/quote/page). This
     NEVER drops the row (keep-both philosophy). The repaired `locator` is written
     back to the row.
  2. **Recomputes the derived key** (`profileKey`/`locatorHash`) from the
     (repaired) stored `locator` under the new NFC canonicalization.
  No-op for NFC/ASCII + finite rows (the vast majority); re-keys NFD-text rows and
  repairs+re-keys invalid rows. `profileKey`/`locatorHash` are NOT
  `@Attribute(.unique)`, so a re-key collision does not violate a constraint.
  Add a `recomputeKey()` helper (+ a `repairedLocator()` helper) to each model (or
  a free function on `Locator`) so the migration, the runtime setters, AND the
  backup-restore path share one code path. **Backup restore** (`PersistenceActor+Backup`)
  must run the same repair+recompute on the decoded `locatorJSON`, so a pre-V10
  backup containing an invalid locator restores repaired.
- **`vreader/Models/Migration/SchemaV1.swift`** — register `SchemaV10` in
  `VReaderMigrationPlan.schemas` + add the V9→V10 `MigrationStage` to `stages`.
- **WI-2 persistence-boundary guarding — the FULL set (Gate-2 High: scope was
  incomplete).** Add a `locator.validate() == nil` guard at every persistence
  entry point, and remove/guard every persistence-bound `?? Locator(...)`
  invalid-locator fallback (audit-confirmed sites):
  - `vreader/Services/PersistenceActor+Highlights.swift`,
    `+Bookmarks.swift`, `+Annotations.swift` (`addAnnotation` persists without
    `validate()`), `+Backup.swift`, and the position-save path.
  - `?? Locator(...)` fallbacks that recreate + persist invalid locators:
    `vreader/ViewModels/EPUBReaderViewModel.swift`,
    `ReadiumEPUBReaderViewModel+Mapping.swift`, `PDFReaderViewModel.swift`,
    `TXTReaderViewModel.swift`, `MDReaderViewModel.swift`. Each: drop/repair an
    invalid locator, never hash+persist it.
- **`contracts/vectors/locator.json` + `IdentityConformanceTests.swift`** —
  **promote** the currently Kotlin-only NFD case (`IdentityConformanceTest.kt`
  hardcoded test) **into the shared vector set** (input NFD via `́`, expected
  NFC) — it is NOT in the shared file today, so this is a new shared vector, not a
  "restore". The Swift suite then asserts it too.
- **`contracts/identity/locator.md`** — flip the "iOS does NOT yet / tracked #109"
  note to "both platforms apply".

### Files OUT of scope
- `Identity.kt` (the Kotlin reference already NFC-normalizes + rejects).
- The Android app (#106) — no Android client yet.
- `BookImporter`/source-bytes Kindle identity (that is feature #108, separate).

## Prior art / project precedent / rejected alternatives

- **Precedent**: SwiftData versioned-schema migrations live in
  `vreader/Models/Migration/SchemaV*.swift` + `VReaderMigrationPlan`
  (`SchemaMigrationPlan`). All prior migrations (V1→V9) were lightweight
  (`stages = []`); V9→V10 is the FIRST custom data-transform stage —
  `V1toV2Migration.swift` already documents exactly how to add one
  (`willMigrate`/`didMigrate`).
- **Precedent**: each annotation/position `@Model` stores BOTH the `Locator`
  (`private(set) var locator: Locator`) AND its derived key, so the migration
  re-derives the key from durable data — no lossy reconstruction.
- **Rejected — precondition-crash on non-finite in `canonicalJSON`**: `canonicalHash`
  is a non-throwing computed property used at 18 sites; a `precondition` could
  crash the app if an unvalidated non-finite locator slips through. Chosen
  instead: NFC in `canonicalJSON` + reject non-finite at the **persistence
  boundary** (`validate()` guard) so invalid locators never get hashed/stored.
- **Rejected — no migration (re-key lazily on read)**: lazy recompute scatters
  the canonicalization across read paths and risks half-migrated state; a one-shot
  `didMigrate` is atomic and auditable.
- **Rejected — skip the migration, accept drift**: rejected by Codex Gate-4 +ADR
  Risk-1; identity must be stable.

## Work-item sequencing

**Atomicity (Gate-2 High):** the `canonicalJSON` NFC change rewrites the live
`canonicalHash` the model setters use immediately — so it MUST ship in the SAME
release as the recompute migration, or existing rows drift to stale keys. WI-1
therefore bundles the hash change + SchemaV10 + the migration as ONE atomic,
independently-shippable PR. WI-2 (non-finite guarding) is additive — it does not
change existing keys and does not worsen the pre-existing non-finite hole, so it
ships after WI-1 safely; it is the FINAL WI that closes #356.

| WI | Deliverable | PR size | Tier |
|---|---|---|---|
| WI-1 | **Atomic hash+migration**: NFC in `Locator.canonicalJSON` + `SchemaV10` + the V9→V10 `.custom` recompute `MigrationStage` (repairs preexisting invalid locators by nulling non-finite fields, then rewrites every `profileKey`/`locatorHash` from the stored `Locator`) + shared `recomputeKey()`/`repairedLocator()` helpers (also used by backup restore) + promote the NFD case into the shared conformance vector + the **keep-both** duplicate policy. Disk-backed migration test (incl. invalid-repair + collision) + backup-restore test + NFC/unicode unit tests + duplicate-coexistence test. | Large | Behavioral |
| WI-2 | Non-finite persistence guarding at ALL entry points + remove/guard ALL persistence-bound `?? Locator(...)` invalid-locator fallbacks. Final WI → closes #356. | Medium | Behavioral |

WI-1 is self-consistent (the hash change AND its migration land together — no
drift window). WI-2 is independent and additive (it closes the non-finite
collision, which exists today regardless of WI-1).

## Test catalogue

- **`vreaderTests/Models/LocatorCanonicalHashTests.swift`** (extend) — NFC: an
  NFD-text locator and its NFC twin produce the SAME `canonicalJSON`/`canonicalHash`;
  ASCII/NFC locators unchanged (regression: existing golden hashes hold).
- **`vreaderTests/Contracts/IdentityConformanceTests.swift`** — the PROMOTED
  shared NFD vector (Kotlin-only → shared) now asserts Swift == expected NFC.
- **`vreaderTests/Models/Migration/SchemaV10MigrationTests.swift`** (new) —
  **DISK-BACKED** per this repo's migration-test convention (Gate-2 High; follow
  `SchemaV9MigrationTests.swift`): write a temp on-disk store under `SchemaV9`,
  seed (a) ASCII rows, (b) NFD-text rows, (c) an NFD/NFC same-position pair,
  (d) a row with a preexisting INVALID (non-finite progression) stored locator;
  close; REOPEN under `ModelContainer(... migrationPlan: VReaderMigrationPlan)`
  with the V10 schema; assert: ASCII keys UNCHANGED; NFD keys recomputed to the NFC
  key with the stored `locator` text untouched; the NFD/NFC pair coexists
  (keep-both, no unique violation); the invalid row REPAIRED (non-finite field
  nulled → `validate()==nil`, key recomputed, **row NOT dropped**); no row lost.
  **Idempotency** = reopen the already-V10 store again, assert keys/rows unchanged
  (NOT "run twice" — a reopened V10 store does not re-run V9→V10).
- **Backup-restore case** — restoring a pre-V10 backup whose `locatorJSON` decodes
  to (i) NFD text and (ii) an invalid locator yields NFC-recomputed + repaired rows
  (same `recomputeKey()`/`repairedLocator()` path as the migration).
- **`vreaderTests/Models/LocatorCanonicalHashTests.swift`** (extend) — NFC twins
  hash identically; **canonical-singleton** equivalence folds; **compatibility-only**
  characters are NOT over-normalized (NFC ≠ NFK*C); KEEP the existing empty-string
  regression (already present, not new coverage); ASCII golden hashes unchanged.
- **`vreaderTests/.../PersistenceActor+{Highlights,Bookmarks,Annotations}Tests`
  / position tests** (extend) — saving a locator that fails `validate()`
  (non-finite) is rejected (not persisted with a colliding key); valid persists.
- **Duplicate-coexistence test** — after the migration produces two same-`profileKey`
  rows, assert the documented policy holds at the real call sites (bookmark
  toggle, highlight fetch-all, backup-restore `profileKey→row` collapse).

## Risks + mitigations

- **R1 — migration performance on a large annotation set.** `didMigrate` touches
  every annotation/position row. Mitigation: it's a one-shot O(n) pass over
  user-scale data (annotations, not books); recompute is a cheap hash. Batch via
  the migration context.
- **R2 — NFD-vs-NFC collision creates a logical duplicate.** Two annotations that
  were distinct under the old (NFD vs NFC) keys collapse to one `profileKey`. No
  `@Attribute(.unique)` → no DB-constraint failure (both rows survive the
  migration). **But the existing app logic is NOT clean LWW (Gate-2 Medium):**
  bookmark toggle removes only the FIRST same-key row
  (`BookmarkListViewModel.swift`), highlight fetches return ALL duplicates
  (`PersistenceActor+Highlights.swift`), and backup-restore collapses same-key
  rows into one `profileKey→row` map (`PersistenceActor+Backup.swift`).
  **Duplicate policy (CHOSEN — the only supported outcome): KEEP-BOTH.** The
  migration recomputes keys and NEVER deletes a row — for the rare NFD/NFC
  same-position pair, both rows survive with the same `profileKey` (no
  `@Attribute(.unique)`, so no DB failure). Rationale: the migration must never
  destroy a user's annotation; de-dup-in-migration would silently delete one. The
  post-collision runtime behavior is exactly today's same-key behavior, pinned by
  tests: bookmark toggle removes the first matching row, highlight fetch returns
  all rows, backup-restore keeps one row per `profileKey` (the
  `profileKey→row`-map collapse is the EXISTING restore behavior — restore is
  inherently last-writer per key, unchanged by this feature). The
  duplicate-coexistence test asserts this single contract at all three call sites.
  (NFD text in saved annotations is rare, so the practical blast radius is tiny.)
- **R3 — a consumer reads `canonicalHash` mid-migration.** SwiftData runs the
  stage before the store opens for app use. Mitigation: standard migration
  ordering; no app reads during `didMigrate`.
- **R4 — the `?? Locator(...)` removal changes reader behavior.** Mitigation: only
  the INVALID-locator path changes (those were already broken — they persisted a
  colliding key); valid locators are unaffected. Covered by reader-position tests.

## Backward compatibility

- **Existing stores**: V9 stores migrate to V10 via the recompute stage. The
  stored `Locator` is durable and unchanged; only the DERIVED key is rewritten.
  ASCII/NFC annotations (the overwhelming majority) get an identical key (no-op).
  NFD-text annotations get a new (correct, stable) key — their old key was already
  buggy (NFD/NFC-unstable), so this is a repair, not a regression.
- **Backups**: backups do NOT serialize `profileKey`/`locatorHash` — they carry
  the locator as `locatorJSON` (`BackupSectionDTOs.swift`), and restore already
  RECOMPUTES the derived key from the decoded `Locator`
  (`PersistenceActor+Backup.swift`). So once `canonicalJSON` is NFC (WI-1), a
  pre-V10 backup restored into a V10 store is automatically NFC-consistent — no
  backup-format change needed. (Confirm in WI-1's tests that restore goes through
  the same `recomputeKey()` path.)
- **Downgrade**: not supported (forward-only schema), consistent with all prior
  vreader migrations.

## Acceptance criteria

1. `Locator.canonicalJSON` NFC-normalizes all string fields; an NFD vs NFC twin
   hash identically (unit test + the promoted shared cross-platform NFD vector
   green on Swift AND Kotlin via `contracts/conformance/run.sh both`).
2. A V9→V10 recompute migration rewrites every `profileKey`/`locatorHash` from the
   stored `Locator` under NFC; ASCII keys unchanged, NFD keys repaired, no row
   lost, idempotent (migration test).
3. A non-finite locator is rejected at the persistence boundary (not stored with a
   colliding key); the `?? Locator(...)` invalid-locator fallbacks are removed.
4. Existing ASCII/NFC annotations + reading positions survive the migration with
   identical identity (no dedupe/toggle regression) — device/integration verified.
5. `contracts/identity/locator.md` reflects "both platforms apply"; bug #356
   (GH #1718) closes.

## Revision history

- v1 (2026-06-17) — initial Gate-1 draft (the #356 iOS obligation; user deferred
  the migration from the #355/#356 PR to this feature).
- v2 (2026-06-17) — Gate-2 round 1 (Codex, read-only plan audit) applied. Model
  assumptions VERIFIED (fields/types exist, SchemaV9 current, keys non-unique +
  durable locator stored). Fixes: **High** — WI split was unsafe (hash change
  before migration → drift): WI-1 now bundles NFC + SchemaV10 + migration ATOMICALLY
  (was 3 WIs, now 2). **High** — persistence-boundary scope incomplete: added
  `PersistenceActor+Annotations` + the `?? Locator(...)` fallbacks in PDF/TXT/MD
  ViewModels to WI-2. **High** — migration test must be DISK-BACKED (per
  `SchemaV9MigrationTests`), not in-memory; idempotency = reopen-V10-unchanged.
  **Medium** — collision is not LWW-clean (toggle/fetch/backup-collapse): added an
  explicit duplicate policy + call-site tests. **Medium** — the NFD vector is
  PROMOTED (Kotlin-only → shared), not "restored"; backups carry `locatorJSON` +
  restore recomputes (no old keys serialized). **Medium** — added canonical-singleton
  / compatibility-only Unicode edge tests; keep the existing empty-string regression.
- v3 (2026-06-17) — Gate-2 round 2 applied (all 3 round-1 Highs confirmed
  resolved). **Medium** — chose ONE duplicate policy: **keep-both, last-touched on
  toggle** (the migration never deletes a row; runtime behavior is today's same-key
  behavior, pinned by call-site tests). **Medium** — the V9→V10 migration (+ backup
  restore) now REPAIRS preexisting invalid locators (V9 stores may already hold
  non-finite locators from the `?? Locator(...)` paths) by nulling the non-finite
  field → recompute, never dropping the row; covered by a disk-backed case + a
  backup-restore case. **Low** — "restored" → "promoted" (the NFD vector is
  promoted Kotlin-only → shared, not restored).
