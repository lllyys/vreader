---
branch: feat/feature-101-wi-1-metrics-cycle
threadId: 019eb580-5de3-74c2-bc88-8b9a5d411ef8
rounds: 2
final_verdict: ship-as-is
date: 2026-06-11
---

# Feature #101 WI-1 — Gate 4 implementation audit

Plan: `dev-docs/plans/20260611-feature-101-reading-time.md` (WI-1:
formatters + lifecycle totals + chrome tap-cycle + per-book persistence
+ the 7 host call sites). Runner: `scripts/run-codex.sh` (codex exec,
read-only). Round-2 session: `019eb589-4d87-7c12-a33e-6f05b0a2c34f`.

## Round 1 findings

| Finding | Severity | Resolution |
|---|---|---|
| `ReaderLifecycleHelper.swift:96` — `beginSession()`'s untracked stats-fetch Task can outlive `close()` / a later reopen and overwrite `totalSecondsAtOpen`/`isFirstSession` with stale data | High | **Fixed** — fetch task tracked + generation-stamped; cancelled and generation-invalidated in `close()`; result dropped unless the generation matches. Regression test `staleFetchFromClosedSessionDoesNotPoisonReopen` (slow counting provider with a poison first total). |
| `ReaderBottomChrome.swift:130` — persisted readout resolved only in `.onAppear`; chrome reuse for a different book keeps the previous book's choice | Medium | **Fixed** — `resolvePersistedReadout()` runs on `.onAppear` AND `.onChange(of: bookFingerprintKey)`; non-book surfaces reset to `.pages`. |
| `ReaderBottomChrome.swift:111` — pressed rounded-fill flash shown while the tap is inert (`timeTrailingLabel == nil`) | Medium | **Fixed** — `MetricsReadoutButtonStyle.showsPressedFill` suppresses the fill in the pinned-pages state. |
| `PDFReaderContainerView+Overlays.swift:103` — "Last page" substitution broke the canonical "N pages left in book" contract | Medium | **Fixed** — uniform string for every count incl. 0; singular grammar only for 1. |
| `ReaderLifecycleHelper.swift:218` — `.readerSessionTimeDidChange` posted with no consumer on this branch | Low | **Accepted with rationale** — the plan's surface-area table places the producer in the WI-1 lifecycle-helper change and the consumer (`ReaderContainerView` mirror → Book details "This session" row) in WI-2b. ~1 post/min is negligible; landing the producer here keeps WI-2b sheet-only. |
| `ReaderBottomChrome.swift:1` — file at 341 lines (> ~300 budget) | Low | **Fixed across r1+r2** — `ReaderToolbarActionObservers` (r1) and `ReaderScrubber` (r2) split into their own files; chrome file now well under budget. |

## Round 2 (verify)

All round-1 High/Medium fixes confirmed in the diff; no new issues
found (the `@MainActor` generation counter, the `.onChange(of:)` form,
and the extracted observer file's notification names were explicitly
checked). One residual Low — file still 312 lines after the r1 split —
resolved by also extracting `ReaderScrubber` into `ReaderScrubber.swift`.

## Verdict

ship-as-is. Tests: 35 new tests green (formatter boundaries incl.
35940/35999/36000, metrics-readout seam, per-book round-trip +
sibling-field preservation, per-book stats fetch, lifecycle
attach/stale-fetch/close-reset) + 130 adjacent regression tests green.
