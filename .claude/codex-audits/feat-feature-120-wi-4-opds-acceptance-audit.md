---
branch: feat/feature-120-wi-4-opds-acceptance
threadId: 019f0405-wi4
rounds: 1
final_verdict: ship-as-is
date: 2026-06-26
---

# Feature #120 WI-4 — Codex audit (OPDS final-WI connected acceptance)

Changed files:
- `android/app/src/androidTest/kotlin/com/vreader/app/opds/ui/OpdsUiRoundTripConnectedTest.kt` (new) — the VM-level live round-trip: OpdsSourcesViewModel save → OpdsBrowseViewModel browse → download → in-library, against the live local OPDS feed.
- `scripts/run-opds-roundtrip.sh` — now runs BOTH the #117 backend round-trip and this WI-4 VM-level acceptance.

## Round 1 — no findings

The acceptance soundly proves the final-WI path:
- `assumeNotNull` skips ONLY when `opdsFeedUrl` is absent; the script always passes it for this gate (no silent false-skip).
- The await/poll helpers are bounded (5s source-save, 20s browse/download) and predicate-based — they can't pass vacuously.
- It drives the REAL stack: `OpdsSourcesViewModel` → `OpdsSourceStore` DataStore → `store.clientFor` real `OpdsClient` → `OpdsBrowseViewModel` → `OpdsAcquisitionService` → `BookImporter` → Room `LibraryRepository`. No stubs.
- Final assertions are strong: the row reaches `library`, Room contains a book, the imported artifact exists on disk, and provenance is `opds://`.

Noted (not a finding): the browse VM marks the row `library` on importer success before the libraryFlow emission corroborates — not a false-green, because the test additionally asserts `repo.listBooks()` + the on-disk artifact after the transition.

**Verdict: ship-as-is.**
