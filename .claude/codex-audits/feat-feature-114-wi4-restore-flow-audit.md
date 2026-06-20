---
branch: feat/feature-114-wi4-restore-flow
threadId: 019ee29e-8c71-7bc0-a55c-8da74b036c7c
rounds: 2
final_verdict: ship-as-is
date: 2026-06-20
---

# Gate-4 implementation audit — feature #114 WI-4 (restore flow, surface D)

Codex (`scripts/run-codex.sh`, gpt-5.5, read-only) audited the restore flow (design surface D
from `vreader-backup-webdav.jsx` RestoreProgress + the confirm alert): `RestoreFlow.kt`,
`RestoreFlowTest.kt`, + the `RestoreProgress.Result.whenLabel` addition in `BackupService.kt`.

## Round 1 — 2 Medium + 3 Low (all fixed)

| severity | issue | resolution |
|---|---|---|
| Medium | missing the designed compact "Restore" top bar | **Fixed**: `RestoreScreen` now owns a `BackupTopBar("Restore", large=false)`. |
| Medium | success copy didn't match the design ("12 of 12 books restored from <date>.") | **Fixed**: `RestoreProgress.Result.whenLabel`; success sub = "… restored from {whenLabel}. Nothing in your library was deleted." |
| Low | progress fraction coerced only for the ring, not the percent/bar | **Fixed**: one `coerceIn(0f,1f)` for all three. |
| Low | two `fillMaxSize` root siblings relied on the caller being a Box | **Fixed**: a self-contained `Column(fillMaxSize)` root (top bar + weighted center + bottom footer). |
| Low | tests missed 58%, partial Done, failed Back | **Fixed**: added those + the date-aware success copy assertion. |

## Round 2 — CLEAN

> "The two prior Mediums are resolved: `RestoreScreen` now owns the compact `Restore` top bar,
> and success copy includes the backup date plus the never-deletes promise. … single coerced
> progress fraction, self-contained root layout, and added assertions."

## Verdict

**ship-as-is.** 7 instrumented `RestoreFlowTest` green on emulator-5554 (confirm merge-copy +
Restore; in-progress 58% + book label + Cancel; success/partial/failed copy + every CTA
callback; dark). "Restore never deletes" appears in the confirm + the success copy. Behavioral
WI — emulator Compose-test verified.
