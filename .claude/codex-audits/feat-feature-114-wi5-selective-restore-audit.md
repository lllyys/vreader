---
branch: feat/feature-114-wi5-selective-restore
threadId: 019ee2a6-949c-7793-9510-650720488df0
rounds: 2
final_verdict: ship-as-is
date: 2026-06-20
---

# Gate-4 implementation audit — feature #114 WI-5 (SelectiveRestoreSheet, surface E)

Codex (`scripts/run-codex.sh`, gpt-5.5, read-only) audited the selective restore picker (design
surface E from `vreader-backup-webdav.jsx` SelectiveRestoreSheet): `SelectiveRestoreSheet.kt`,
the `AppSheet` footer-slot addition in `BackupScaffold.kt`, `SelectiveRestoreSheetTest.kt`.

## Round 1 — 2 Medium + 2 Low (all fixed)

| severity | issue | resolution |
|---|---|---|
| Medium | `b.progress` used unclamped (bar + percent) | **Fixed**: `coerceIn(0f,1f)` once. |
| Medium | rows clickable but not exposed as checkbox/selectable a11y | **Fixed**: `Modifier.selectable(selected, role = Role.Checkbox)`. |
| Low | retry affordance only a 20dp icon | **Fixed**: a 44dp box w/ the click + `semantics{contentDescription="Retry"}`. |
| Low | retry test didn't prove it avoids the row toggle | **Fixed**: `retry_failedBook_invokesRetry_notRowToggle` (asserts `onRetry("m5")` AND `onToggle == null`). |

Clean (round 1): the footer-slot pins the Restore CTA below the scroll; the per-book copy
matches the design; stateless (books + selected set + callbacks).

## Round 2 — CLEAN

> "All Medium round-1 findings are resolved … Progress computed once and reused; rows use
> `selectable(role=Role.Checkbox)`; retry is a 44dp target with its own semantics; regression
> test verifies retry does not toggle the row. No new Critical/High/Medium found."

## Verdict

**ship-as-is.** 10 instrumented `SelectiveRestoreSheetTest` green on emulator-5554 (4 per-book
states, footer total + recompute, row-toggle id, restore, select-all/deselect-all, retry id +
no-toggle, dark). Final WI — completes feature #114's 5 designed surfaces.
