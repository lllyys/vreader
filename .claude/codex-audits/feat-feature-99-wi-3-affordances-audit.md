---
branch: feat/feature-99-wi-3-affordances
threadId: 019eb63e-d78b-7d02-9b37-3e41470aa6d3
rounds: 2
final_verdict: ship-as-is
date: 2026-06-11
---

# Feature #99 WI-3 — Gate 4 implementation audit

Plan: `dev-docs/plans/20260611-feature-99-translation-settings-reentry.md`
(WI-3: the two re-entry affordances + the granularity/provider mirrors).
Runner: `scripts/run-codex.sh`. Round-2 session: `019eb649-f73c-7c33-8a4b-efd9aa44f64e`.

## Round 1 findings

| Finding | Severity | Resolution |
|---|---|---|
| `ReaderContainerView+Sheets.swift:367` — the provider-name fetch left the previous name visible until completion (stale flash on provider switch) and never invalidated on dismiss (late completion wrote into closed-popover state) | Medium | **Fixed** — `providerDisplayName = nil` before the fetch; the generation bumps on EVERY onMore toggle (open and close); the apply guards generation + `showMorePopover`. |
| `ReaderMorePopoverParts.swift:75` — the shared action funnel never observed `.readerMoreTranslationSettings`, leaving the container-level effect route dead | Low | **Fixed** — observer added; the effect round-trips through the funnel. |
| `ReaderMorePopover.swift` 387 / `ReaderTopChrome.swift` 302 lines | Low | **Fixed** — row rendering split to `ReaderMorePopover+Rows.swift` (UIKit-gated extension) and the pill style to `BilingualPillButtonStyle.swift`; 252/275 lines now. |
| `.readerMoreBilingual` doc described row posts as payload-free | Doc | **Fixed** — doc notes every row post now carries the key; only the settings notification REQUIRES filtering. |

Round 1 explicitly confirmed: cluster tint/divider geometry per design,
pill pressed alphas correct, no observer breaks on the new userInfo, no
double-draw in the cluster loop, no MainActor/Sendable defect.

## Round 2 (verify)

Clean — all fixes confirmed; UIKit gating + access levels of the moved
members appropriate.

## Verdict

ship-as-is. 92 tests green across 6 suites (the new row-contract suite
incl. the keyed-notification + granularity-payload pins; updated 8-row
contract pins; popover/chrome regressions).
