---
branch: fix/triage-bug-265-azw3-position-resume
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-25
---

## Scope

Docs-only triage filing. Adds one new summary row + one Open-Bug-Details
entry to `docs/bugs.md` for **Bug #265** (AZW3/MOBI reading position not
saved or restored on reopen, High). Touches `docs/bugs.md` only, plus
`project.yml` / `project.pbxproj` (version bump 3.39.9/630 → 3.39.10/631).

**No Swift source files changed.** The audit-gate hook fires on
`project.pbxproj` — false positive of the Swift-file heuristic. Manual
mini-audit.

## Manual audit evidence

### Investigation done at triage time

1. **GH issue context** — the user pointed at no prior issue; this is a
   fresh symptom ("azw3 cannt resume the process after reopen it") flagged
   highest priority.
2. **Save/restore API located**: `ReaderPositionService.saveNow(locator:)`
   (`ReaderPositionService.swift:73`), `PersistenceActor.savePosition`
   (`PersistenceActor+ReadingPosition.swift:31`), `loadPosition`
   (`PersistenceActor+ReadingPosition.swift:13`).
3. **Per-format restore-on-open confirmed for the 4 native formats**:
   PDF (`PDFReaderViewModel.restorePosition` → `loadPosition`), TXT
   (`TXTFileLoader` → `loadPosition`), MD (`MDFileLoader` → `loadPosition`),
   EPUB (`EPUBFileLoader.restorePosition` → `loadPosition`). **No Foliate
   loader appears in the restore-side results.**
4. **Save callers**: only `ReaderLifecycleHelper.saveNow` (lines 95, 122),
   composed by the 4 native VMs **and** `FoliateReaderViewModel` — but the
   Foliate VM is constructed ONLY by `FoliateReaderHost`
   (`ReaderFormatHosts.swift:255`).
5. **Dead-code confirmation**: `FoliateReaderHost` is referenced nowhere
   except a comment in `FoliateReaderContainerView.swift:33`. The dispatcher
   (`ReaderContainerView.swift:942`, `case .foliateWeb`) instantiates
   `FoliateBilingualContainerView`, NOT `FoliateReaderHost`. Bug #262/#1136's
   own FIXED note states "`FoliateReaderContainerView`/`FoliateReaderHost`
   are DEAD code, never instantiated."
6. **Live-path persistence = absent**: grep
   `savePosition|saveNow|ReadingPosition|loadPosition|positionService|ReaderLifecycleHelper`
   across `FoliateBilingualContainerView.swift`,
   `FoliateBilingualContainerView+BottomChrome.swift`,
   `FoliateSpikeView.swift`, `FoliateBottomChromeSeek.swift` → **0 hits**.
7. **`.readerPositionDidChange` is not a persistence trigger**: its
   observers (Bilingual prefetch, DebugBridge snapshot, AI context) do not
   call `savePosition`/`saveNow`. The only `saveNow` in any observing file
   is `TXTReaderViewModel:657` (that VM's own lifecycle save, not driven by
   observing the notification). So #1136's `.readerPositionDidChange`
   wiring feeds live AI/snapshot context only — it does not persist a
   `ReadingPosition`.

### Correctness checks

1. **Bug-vs-feature** — reading-position persistence (save + restore) IS
   implemented project-wide (PDF/TXT/MD/EPUB + the dead Foliate trio). The
   LIVE AZW3 path simply never wired it. Implemented-elsewhere-but-broken-
   for-AZW3 = **bug**, recorded in `docs/bugs.md` — not a feature.
2. **No duplicate** — no existing row covers AZW3 position resume/restore.
   The nearest, **#262/#1136**, wired locator NAVIGATION (tap TOC row → jump)
   + live position REPORTING; it did NOT wire cross-session PERSISTENCE
   (save to `ReadingPosition` + restore-seek on reopen). Cross-referenced,
   not duplicated.
3. **Not a reopen** — #262/#1136 delivered exactly its scope (TOC + nav +
   reporting); position persistence was never in that scope. Filing a new
   bug with cross-references is the correct lineage.
4. **Regression class noted** — third capability dropped by the Feature #56
   WI-11 live-container swap, after #260 (bottom chrome) and #262/#1136
   (TOC/nav/reporting). Recorded in the row for pattern visibility.
5. **Severity** — High. User flagged highest priority; core reading
   continuity broken for an entire major format (every reopen loses place).
   Repo severity vocabulary tops out at `severity:high` (no critical tier).
6. **Rule 51** — fix is pure wiring of existing persistence (no new UI) →
   not design-blocked; noted in the row.
7. **GH mirror** — #1148 (`bug` + `severity:high`) created; stamped in Notes
   (hook `check_gh_issue_mirror.sh` passed on the edit).
8. **Bug ID** — max on main was 264 (`#264 / GH #1141`); 265 is next free.
   No collision.
9. **No fix attempted** — classification + root-cause + fix direction only
   (triage is classification, not execution).
10. **Version bump** — 3.39.10 / build 631 (patch — docs / tracker triage).
    `xcodegen generate` + `xcodebuild build` SUCCEEDED on iPhone 17 Pro
    Simulator (Debug).

## Verdict

ship-as-is — documentation only, one bug filing, no code risk. Manual
fallback used because there is nothing to send to Codex.
