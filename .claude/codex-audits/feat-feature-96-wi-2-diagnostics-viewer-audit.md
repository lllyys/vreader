---
branch: feat/feature-96-wi-2-diagnostics-viewer
threadId: 019eb036-1ba0-7ac0-ab83-2ac999d843fb
rounds: 2
final_verdict: ship-as-is
date: 2026-06-10
---

# Gate-4 Codex audit — feature #96 WI-2 (in-app Diagnostics log viewer + Settings entry)

Independent audit via `scripts/run-codex.sh` (gpt-5.4), read-only sandbox.
Author = implementing Claude session; auditor = Codex (rule-48 separation).

## Round 1 — session `019eb036-1ba0-7ac0-ab83-2ac999d843fb`

| file:line | severity | issue | resolution |
|---|---|---|---|
| DiagnosticsLogViewModel.swift:96 | High | Export collapsed the `Errors` chip to `store.exportText(level: .error)`, dropping visible `.fault` rows from the shared file. | **Fixed** — added `DiagnosticsLogStore.exportText(entries:)`; the VM now exports `filteredEntries` (the same set the chip shows, incl. `.fault`). Test `exportUnderErrorsChipIncludesFault`. |
| DiagnosticsLogView.swift:164 | High | `firstIndex(of:)` row identity collided for value-equal entries → wrong/multiple rows expand together. | **Fixed** — `IdentifiedDiagnosticsEntry{id,entry}` threaded through `DiagnosticsDayGrouper`; the view expands by `item.id` (position in the filtered list). Tests `groupingPreservesAssignedIdentity`, `identifiedEntriesAreDistinctForValueEqualRows`. |
| SettingsView.swift:300 | Medium | Rule-51: a separate one-row `Support` group left `About` intact — not the committed design, which regroups About *under* Support. | **Fixed** — single `Support` group = [Diagnostics, Help & Feedback, Version]; `SheetSectionContract.appSettings` updated to `[Cloud & Sync, AI, Reading, Support]`. |
| DiagnosticsLogViewModel.swift:113 | Medium | Filtered footer scope dropped the active-filter suffix the design calls for. | **Fixed** — filtered scope now `Showing X of N · <category level>`. Test `footerScopeReflectsFiltering`. |
| DiagnosticsLogView.swift:176 | Low | Synchronous main-actor UTF-8 encode + temp-file write, with a silently-swallowed failure. | **Fixed** — `nonisolated writeExport` in `Task.detached`, hop back to present; failure → `exportFailed` alert. |

No raw-message egress leak found: on-screen raw text is fine; Copy-entry and
the share file both go through `DiagnosticsRedactor`.

## Round 2 — session `019eb040-2126-7013-ae1c-d35582e208e5`

3 of 5 round-1 findings confirmed RESOLVED (filtered-export, row identity,
Support/About regroup); the Low (off-main write) confirmed resolved with no new
concurrency/Sendable bug. Two NEW Mediums, same root:

| file:line | severity | issue | resolution |
|---|---|---|---|
| DiagnosticsLogViewModel.swift:120 | Medium | Footer scope hardcodes `this session`; design mock illustrates a window label. | **Fixed** — single-sourced `DiagnosticsLogStore.captureScopeLabel`. |
| DiagnosticsLogStore.swift:74 | Medium | Export header hardcodes `(current session)`, diverging from the footer's string. | **Fixed** — export header now uses the same `captureScopeLabel`. |

**Design-faithfulness decision (documented in the plan):** the label is
`"this session"`, NOT the mock's "last 24 h". WI-1's Gate-2 Critical correction
scoped capture to `OSLogStore(scope: .currentProcessIdentifier)` — the current
process's entries, not a rolling 24-hour window — so "last 24 h" would be
factually wrong. "this session" is the approved, accurate, single-sourced
descriptor for both the footer and the export header.

## Device-verification finding (Gate 5, found + fixed before merge)

Acceptance testing on iPhone 17 Pro Sim surfaced a bug the audits couldn't (it's
a presentation-depth runtime issue): the export trigger embedded a
`UIActivityViewController` (`ShareActivityView`) in a `.sheet`, which rendered a
**blank white sheet** from this depth (Settings `.sheet` → `NavigationStack`
push → `.sheet`). Refactored to the native iOS-17 `ShareLink` with a
reactively-prepared redacted file URL (off-main on appear + each filter change).
Re-verified on device: the system share sheet presents correctly with the
`vreader-log-<date>.txt` (6 KB) payload. Evidence:
`dev-docs/verification/feature-96-20260610.md`.

## Verdict

**ship-as-is.** All Critical/High/Medium findings across both rounds fixed and
pinned by tests (100 tests green across the 7 Diagnostics + Settings suites); the
device-verification share bug fixed via `ShareLink`. Remaining design wording
resolved by an explicit, documented source-of-truth decision rather than
reproducing a factually-incorrect mock label.
