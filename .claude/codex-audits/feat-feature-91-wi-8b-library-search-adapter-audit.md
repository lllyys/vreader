---
branch: feat/feature-91-wi-8b-library-search-adapter
threadId: 019e9309-babb-7743-9c95-8fb04e5f367f
rounds: 2
final_verdict: ship-as-is
date: 2026-06-04
---

# Codex Audit — Feature #91 WI-8b (slice 3: LibrarySearchBackend production path)

Gate-4 implementation audit (rule 47). Independent Codex runner via
`scripts/run-codex.sh -e high` (author/auditor separation, rule 48; rule-53
stdin-isolated watchdog).

## Scope

WI-8b slice 3 — the production `LibrarySearchBackend` the search_other_books tool
(WI-6b) depends on:

- `vreader/Services/AI/Tools/LibrarySearchBackendAdapter.swift` (new) — forwarding
  glue over `LibraryPersisting` + `SearchIndexStore` + `SearchService`, reached
  through two narrow seams (`SearchIndexReading` / `IndexedBookSearching`) the
  concrete types conform to via empty extensions (compile-time drift detection).
  libraryBooks → fetchAllLibraryBooks; indexState → the 3 store reads mapped into
  `LibraryIndexState`; restoreSegmentOffsets → the service; search → page 0,
  pageSize = limit. The index-coverage RISK lives in the already-tested pure
  `LibraryBookSearchGate`.
- `vreaderTests/Services/AI/Tools/LibrarySearchBackendAdapterTests.swift` (new).

## Round 1 — findings (threadId 019e9309-babb-7743-9c95-8fb04e5f367f)

**No production-code findings.** The auditor confirmed by exact-signature
inspection that both empty-extension conformances compile (`SearchIndexStore` /
`SearchService` match the seam protocols), the mapping forwards into the right
`LibraryIndexState` slots, search forwards page 0 / pageSize = limit, and the
Sendable story holds. Both findings were test-strengthening:

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| LibrarySearchBackendAdapterTests.swift | **Medium** | `indexStateMaps` used symmetric `true/true`, so an `isIndexed↔requiresReindex` swap would still pass; the stub ignored the forwarded key. | **Fixed.** `RecordingIndex` records the key of all 3 reads; the test now uses ASYMMETRIC `indexed:false`/`reindex:true` and asserts `keys == ["the-key", ×3]`. |
| LibrarySearchBackendAdapterTests.swift | Low | `restoreForwards` dropped the offsets payload. | **Fixed.** `RecordingSearch` captures `restoredOffsets`; the test asserts `== [0:0, 1:4096]`. |

## Round 2 — verification (threadId 019e931d-599a-7592-ad47-b6dc25b32e82)

**RESOLVED.** No new issues — both test gaps closed (asymmetric mapping + key
forwarding on all three reads; the offsets payload asserted).

## Verdict

**ship-as-is.** Zero open Critical/High/Medium after round 2. `LibrarySearchBackendAdapterTests`
green (4 tests: libraryBooks forwarding, indexState mapping into the right slots +
key-forwarding, restore forwarding the fingerprint + offsets, search at page 0 /
pageSize = limit). The empty-extension conformances give compile-time drift
detection if the concrete `SearchIndexStore`/`SearchService` signatures change.

Both production adapters (BookContentProvider + LibrarySearchBackend) are now
complete. The remaining WI-8b work (the registry builder + the
`AIChatViewModel.sendMessage` branch + citation suppression + Gate-5 device
verification) completes Feature #91 to `DONE`/`VERIFIED`.
