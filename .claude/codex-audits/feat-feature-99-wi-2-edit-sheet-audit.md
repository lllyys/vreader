---
branch: feat/feature-99-wi-2-edit-sheet
threadId: 019eb61f-a3e2-7e90-bf35-a0613f1b5513
rounds: 2
final_verdict: ship-as-is
date: 2026-06-11
---

# Feature #99 WI-2 — Gate 4 implementation audit

Plan: `dev-docs/plans/20260611-feature-99-translation-settings-reentry.md`
(WI-2: the edit-framed setup sheet). Runner: `scripts/run-codex.sh`.
Round-2 session: `019eb629-f23b-71f2-a564-0dc7989f6340`.

## Round 1 findings

| Finding | Severity | Resolution |
|---|---|---|
| `BilingualSetupSheet+EditMode.swift:119` — the context strip italicised the whole line; the design italicises only the serif book-title run | Medium | **Fixed** — concatenated runs: plain 11.5pt prefix + italic Source Serif 4 title, single line tail-truncated. |
| `BilingualLanguagePickerCell.swift:79` — the cached-badge ring used `theme.chromeColor`; the design pins it to the sheet surface | Low | **Fixed** — `theme.sheetSurfaceColor`. |
| `BilingualSetupSheet.swift` at 314 lines (> ~300) | Low | **Fixed** — `TranslationGranularity` display-label extension moved to `BilingualSetupSheetState.swift`; the sheet is 293 lines. |

Round 1 explicitly confirmed: first-enable keeps the default trailing
close button and renders unchanged; the `normalised()`/dirty
interaction is covered by the WI-1 canonicalisation; the state-file
extraction kept behavior + doc comments; unknown cached keys are safe.

## Round 2 (verify)

Clean — all three fixes confirmed; no new issues.

## Verdict

ship-as-is. 31 tests green across the sheet suites (12 edit-mode pins
incl. first-enable-unchanged + CTA/strip/badge/caption rules + cost
strip copy; existing first-enable suite; language registry suite).
