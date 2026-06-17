---
branch: feat/feature-108-wi2-importer-sourcekey
threadId: 019ed6a2-ea00-79d3-8bbd-ab5ddd13e08b
rounds: 3
final_verdict: ship-as-is
date: 2026-06-18
---

# Gate-4 audit — feature #108 WI-2 (+ folded-in WI-3)

WI-2 makes `BookImporter` compute + persist the converted-Kindle source-bytes
canonical identity (`Book.sourceCanonicalKey`). Round-1 surfaced that WI-2 must
not ship without WI-3 (a backup taken between them silently loses the field), so
WI-3 (backup-manifest carry + restore re-attach) was folded into this PR — making
this the **final WI** of feature #108.

Codex (gpt-5.4, high reasoning, read-only) — 3 rounds. Sessions: round 1
`019ed6a2-…`, round 2 `019ed6b0-…`, round 3 `019ed6b6-…`.

## Round 1 — 3 Medium + 1 Low

| file:line | sev | issue | resolution |
|---|---|---|---|
| BookImporter.swift:289 | Medium (M1) | Re-importing a pre-#108 converted book did not backfill `sourceCanonicalKey` (dedupe always returned `existing`, which was nil). | Added `PersistenceActor.setSourceCanonicalKey(_:forBookWithKey:)`; the dedupe branch backfills when `existing == nil && computed != nil` and returns the new key. Test `dedupeBackfillsNilSourceCanonicalKey`. |
| BackupDataCollector.swift:211 | Medium (M2) | WI-2 made the field real persisted data, but backup/export + remote-only restore omitted it → silent loss before WI-3. | **Folded WI-3 in**: threaded the field through `BackupBookProjection`, `BackupLibraryEntry` (Codable optional, back-compat, no schema bump), `BackupDataCollector`, `makeRemoteOnlyRecord`, `PersistenceActor+RemoteOnly`, + a materialize re-attach in `SelectiveRestoreCoordinator`. Tests: manifest carry round-trip + old-manifest-decodes-nil. |
| BookImporter.swift:189 | Medium (M3) | The new source hash ran on the caller (@MainActor importer entry) — a second blocking full-file read. | Wrapped the source `ContentHasher.hash` in `Task.detached`. |
| BookImporter.swift:179 | Low (M4) | Source key computed AFTER conversion, not before as planned. | Moved the source hash + key computation BEFORE `MobiEPUBConverter.convertToFile`. |

Round 1 confirmed the core contract correct (source bytes, normalized `.azw3`,
native/non-Kindle nil, dedupe preservation).

## Round 2 — 1 Medium (new, from the WI-3 threading)

| file:line | sev | issue | resolution |
|---|---|---|---|
| PersistenceActor+RemoteOnly.swift:135 | Medium (M5) | Phase-1 selective restore skipped existing rows with a bare `continue`, so an unselected manifest entry matching a pre-#108 existing row never backfilled `sourceCanonicalKey` from the manifest — the remaining silent-loss path. | The existing-row branch now backfills `existingBook.sourceCanonicalKey` when the stored row is nil and the record carries a non-nil key (without downgrading `fileState`). Test `preplantBackfillsSourceCanonicalKeyOnExistingNilRow`. |

Round 2 confirmed M1–M4 resolved; Codable back-compat correct; title/provenance
update paths don't rebuild-and-drop the field.

## Round 3 — CLEAN

"No new Critical/High/Medium findings. M5 is resolved." Verified the backfill only
fires on a nil→non-nil transition (never overwrites a non-nil key), doesn't touch
`fileState`, and the per-record `save()` matches the method's existing
partial-success transaction model. All write paths for `sourceCanonicalKey`
checked: export carries it, importer dedupe backfills only nil rows, selective
restore preplant preserves/backfills on existing matches.

## Verdict

**ship-as-is.** 3-round real-Codex audit; all 5 findings (M1–M5) resolved. The
feature ships complete (WI-2 + WI-3 together), with no silent-loss path remaining
for the converted-Kindle source identity.
