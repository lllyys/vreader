---
branch: feat/feature-109-wi2-nonfinite-guard
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-06-17
---

# Gate-4 audit — feature #109 WI-2 (non-finite locator persistence guarding)

WI-2 (final WI) closes bug #356: never persist a non-finite (invalid) locator,
which canonicalizes the same as a valid missing-progression one and would collide
on the derived key.

## Codex availability

Codex CLI returned `ERROR: You've hit your usage limit … try again at Jun 18th
11:38 AM` (session `019ed634-…` for the WI-1 round-3 attempt; the quota persists).
The independent Codex auditor is genuinely unavailable until the quota resets, so
per `.claude/rules/53-codex-runner-isolation.md` + rule 47's manual-fallback
provision this WI's audit is a manual mini-audit with recorded evidence. The
change is mechanical (repair-at-boundary + fallback repairs) and fully RED→GREEN
+ regression tested.

## Manual Audit Evidence

**Files read / verified**:
- `vreader/Services/PersistenceActor+{Highlights,Bookmarks,Annotations,Backup}.swift`,
  `PersistenceActor+ReadingPosition.swift` (`savePosition` + `saveVReaderLocator`)
- `vreader/ViewModels/{EPUBReaderViewModel,MDReaderViewModel,PDFReaderViewModel,TXTReaderViewModel}.swift`,
  `ReadiumEPUBReaderViewModel+Mapping.swift`
- `vreader/Models/Locator.swift` (`repairedForCanonicalization`, `validate`)

**Symbols verified**: `repairedForCanonicalization()` nulls only non-finite
`progression`/`totalProgression` and is a no-op (returns `self`) for finite
locators; `validate()` returns `.nonFiniteProgression` for the invalid case.

**Design — two layers**:
1. **Authoritative**: every PersistenceActor entry point that writes a `Locator`
   shadows the param with `let locator = locator.repairedForCanonicalization()`
   immediately after the fingerprint guard, so all downstream key derivation +
   row construction use a valid locator. Sites: `addHighlight`, `addBookmark`,
   `addAnnotation`, `savePosition` (live), `saveVReaderLocator` (legacy leg),
   `decodeLocator` (covers all three backup-restore paths; the inline
   position-restore decode flows through the now-guarded `savePosition`).
2. **Defense-in-depth**: each reader ViewModel's `?? Locator(...)` fallback (which
   previously RECREATED the invalid locator the validated factory had rejected)
   now appends `.repairedForCanonicalization()`, so an invalid locator never even
   propagates in memory. Sites: EPUB/MD/PDF/TXT `makeLocator` + the Readium
   mapping `legacy` fallback.

**Edge cases checked**:
- Finite locator → repair is identity (guard clause) → zero behavior change for
  the valid majority. Confirmed by 12+ green regression suites.
- Non-finite progression → nulled; href/cfi/offsets/anchor preserved (asserted).
- Fingerprint guard ordering: repair doesn't alter `bookFingerprint`, so the
  `== key`/`== expectedKey` guards remain valid before/after.
- Dedup: profileKey derived from the repaired locator → an invalid locator now
  dedups against its valid missing-progression twin (the #356 intent).
- Backup authored by a pre-fix build carrying a non-finite locator → repaired on
  restore.

**Concurrency**: all entry points are actor-isolated; `repairedForCanonicalization`
is a pure value transform. No new shared mutable state; no Sendable concern.

**Tests added**: `PersistenceActorNonFiniteLocatorGuardTests` (RED→GREEN) — 4
tests asserting `addHighlight`/`addBookmark`/`addAnnotation`/`savePosition` store
a VALID, key-consistent locator from a non-finite input. RED confirmed (all 4
failed pre-fix), GREEN after the guards.

**Regression**: PDF/MD/Readium/EPUB/TXT reader-VM suites + PersistenceHighlight/
Bookmark/Dedupe/HighlightLookup + BackupDataCollectorRestorer/ReadingHistory all
green.

**Risks accepted**: `repairedForCanonicalization` repairs only non-finite fields,
not other validation failures (negative page / inverted UTF-16 range). Those are
not the #356 collision and do not arise from the production code paths here
(PDFKit page indices ≥ 0; factories build well-formed ranges). If such a value
ever reached a boundary it would be stored as-is — out of scope for #356, no
regression vs prior behavior.

## Verdict

**ship-as-is.** The two-layer guard makes it impossible to persist a non-finite
locator through any entry point, closing the #356 collision. Mechanical change,
no new concurrency, finite-locator behavior unchanged, RED→GREEN + broad
regression coverage.
