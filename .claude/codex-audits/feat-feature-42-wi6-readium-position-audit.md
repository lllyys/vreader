---
branch: feat/feature-42-wi6-readium-position
threadId: codex-exec-readonly
rounds: 2
final_verdict: ship-as-is
date: 2026-05-29
---

# Gate-4 Implementation Audit — Feature #42 WI-6 (Readium position save/restore)

Independent Codex audit (`codex exec --sandbox read-only`) of WI-6: reading-position
save + restore for the Readium EPUB engine via the engine-agnostic `VReaderLocator`
envelope (SchemaV8 `vreaderLocatorData` column). Author = implementing session;
auditor = separate `codex exec` process (rule-48 author/auditor separation).

Changed files:
- `vreader/ViewModels/ReadiumEPUBReaderViewModel+Mapping.swift` (NEW) — pure Readium `Locator` ↔ `VReaderLocator` mapping.
- `vreader/ViewModels/ReadiumEPUBReaderViewModel.swift` — debounced save + restore + closeAndFlush + persistence injection.
- `vreader/Services/PersistenceActor+ReadingPosition.swift` — `saveVReaderLocator`/`loadVReaderLocator` dual-write + `VReaderLocatorPersisting` conformance.
- `vreader/Services/EPUB/ReadingPositionPersisting.swift` — new dedicated `VReaderLocatorPersisting` protocol.
- `vreader/Views/Reader/ReadiumEPUBHost.swift` — modelContainer wiring, restore-before-mount `initialLocation`, `onLocationChange` callback, `closeAndFlush` in `.onDisappear`.
- `vreader/Views/Reader/ReaderContainerView.swift` — threads `modelContainer` into both dispatch sites.
- `vreaderTests/ViewModels/ReadiumEPUBReaderViewModelTests.swift` (NEW) — mapping + PersistenceActor dual-write + audit-fix regression tests.

## Round 1 — 2 High / 2 Medium

| File | Severity | Issue | Resolution |
|---|---|---|---|
| ReadiumEPUBReaderViewModel.swift:238 | **High** | Debounced save could become an unawaited in-flight persist; `closeAndFlush()` could return before the final position was written (dismiss-during-debounce loses position). | FIXED — `closeAndFlush()` snapshots the `saveTask`, cancels it, flushes a still-pending locator via `await persist(pending)`, then `await inFlight?.value`. Debounce Task now `await self.persist(loc)` directly (removed the `persistNow` fire-and-forget wrapper). Exactly one path persists (pending is nil once the task consumes it) → no double-persist. |
| PersistenceActor+ReadingPosition.swift:50 | **High** | Legacy `savePosition` left a stale `vreaderLocatorData` envelope; a flag-ON restore could resurrect a Readium position predating a newer legacy write. | FIXED — `savePosition`'s existing-row branch sets `existing.vreaderLocatorData = nil`. `loadVReaderLocator` then returns nil → Readium opens at start, ceding to the authoritative legacy `locator`. |
| PersistenceActor+ReadingPosition.swift:78 | **Medium** | `saveVReaderLocator` lacked `savePosition`'s fingerprint-mismatch guard (book X's envelope could be written into book Y). | FIXED — guards both `vreaderLocator.fingerprintKey == bookFingerprintKey` AND `legacyLocator.bookFingerprint.canonicalKey == bookFingerprintKey`, throws `PersistenceError.recordNotFound` otherwise. |
| ReadingPositionPersisting.swift:49 | **Medium** | Protocol default no-op/nil envelope methods silently dropped Readium persistence for any non-`PersistenceActor` conformer — a hidden data-loss mode. | FIXED — removed the defaults; new dedicated `VReaderLocatorPersisting` protocol (Sendable), conformed ONLY by `PersistenceActor`. `ReadiumEPUBReaderViewModel.persistence` is now `(any VReaderLocatorPersisting)?` — the compiler enforces a real envelope store. |

Round-1 also confirmed (no bug): restore ordering is correct (`restoredLocator` assigned before `open()`; representable built only at `.ready`, so no first-render-with-nil window), and all model assumptions match the codebase.

## Round 2 — clean

**No new Critical/High/Medium findings.** All four round-1 fixes confirmed resolved:
- Fix 1 — `closeAndFlush()` handles both pending + already-in-flight debounce paths without double-persist.
- Fix 2 — `savePosition()` clears stale `vreaderLocatorData`; the Readium path uses `saveVReaderLocator()`, not `savePosition()`.
- Fix 3 — fingerprint guards cover both envelope + legacy locator; no other production envelope write path exists.
- Fix 4 — protocol split is clean; nothing else relied on the removed defaults; `extension PersistenceActor: VReaderLocatorPersisting {}` is valid with witnesses in the existing extension.

## Verdict

**ship-as-is.** Two audit rounds, zero open Critical/High/Medium. Regression tests added
for every behavioral fix (`legacySavePosition_clearsStaleReadiumEnvelope`,
`saveVReaderLocator_mismatchedFingerprint_throws`,
`closeAndFlush_persistsPendingDebouncedSave`). Test gate green: 60 tests / 5 suites.
