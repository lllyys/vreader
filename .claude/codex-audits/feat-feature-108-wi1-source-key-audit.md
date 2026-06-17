---
branch: feat/feature-108-wi1-source-key
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-06-18
---

# Gate-4 audit — feature #108 WI-1 (Book.sourceCanonicalKey + SchemaV10)

WI-1 (foundational): adds the additive optional `Book.sourceCanonicalKey: String?`
(converted-Kindle cross-platform identity) + a SchemaV10 lightweight migration +
`BookRecord` threading. No importer logic yet (WI-2 populates the field).

## Codex availability

Codex backend was in a persistent outage at audit time —
`chatgpt.com/backend-api/codex/responses` returned HTTP 404 via Cloudflare across
~6 attempts over ~30 min (incl. trivial pings; one ping had succeeded ~40 min
earlier, so transient backend outage, not quota). Per rule 47 / rule 53
manual-fallback. WI-1 is a low-risk additive change; the riskier WI-2/WI-3 will
get a real Codex audit when the backend recovers (a wakeup is scheduled).

## Manual Audit Evidence

**Files changed**: `Book.swift` (+field, +init param default nil, +assignment),
`Migration/SchemaV10.swift` (new VersionedSchema, models = SchemaV9.models),
`Migration/SchemaV1.swift` (register V10, stages stay `[]`, comment),
`App/VReaderApp.swift` (Schema(SchemaV10.models)), `PersistenceActor.swift`
(`BookRecord` +field +init-param-default-nil + both mappings: insertBook
record→Book and bookToRecord Book→record), + tests.

**Correctness**:
- Additive optional field; init param defaults `nil` → all existing `Book(...)` /
  `BookRecord(...)` callers compile + behave unchanged (verified: BookImporter +
  persistence suites green).
- `BookRecord` `Equatable` is auto-synthesized over the new field; existing
  comparisons stay equal because callers pass nil. Verified green.
- SchemaV10 registered as the plan tail; V9→V10 is additive → SwiftData
  lightweight migration fires (disk-backed test
  `v9StoreReopensUnderV10WithNilSourceKey` seeds a V9 store, reopens under V10 +
  the plan, asserts the row survives with `sourceCanonicalKey == nil`). The app
  container (`Schema(SchemaV10.models)` + plan) builds + the migration runs — the
  test passing proves the plan is valid (no schema-rejection).
- Round-trip test proves the field persists through insert→fetch and threads both
  BookRecord↔Book mapping directions.

**Edge cases**: native/non-Kindle import → nil (tested); existing V9 books
grandfather to nil (tested); no behavior change for the finite/native majority.

**Migration distinction from #109**: #109's SchemaV10 was shape-identical (custom
stage never fired → launch backfill). THIS SchemaV10 is a genuine additive column
→ lightweight migration fires. #109's shape-identical V10 was deleted; no conflict.

**Concurrency**: BookRecord is `Sendable`; the field is a `String?`. No new
shared mutable state. PersistenceActor mappings unchanged in isolation.

**Risks accepted**: none material for WI-1 (pure additive plumbing).

## Verdict

**ship-as-is.** Low-risk additive foundation; RED→GREEN + regression-clean.
Real Codex audit deferred to WI-2/WI-3 (the behavioral logic) when the backend
recovers.
