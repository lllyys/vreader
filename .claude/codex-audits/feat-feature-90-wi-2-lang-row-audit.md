---
branch: feat/feature-90-wi-2-lang-row
threadId: 019e987f-c638-77c1-be3c-764b9322ca30
rounds: 2
final_verdict: follow-up-recommended
date: 2026-06-05
---

# Gate-4 audit — Feature #90 WI-2 (Summarize-tab language control row + popover)

WI-2 of #90: the UI control beneath the scope chips — `AISummaryLangRow` (a
`BilingualLanguage` pill + a Single/Bilingual segmented toggle) + `AISummaryLangPopover`
(the `BilingualLanguage.all` grid) + the `AISummaryTabView` wiring. Maps the control
to the WI-1 VM: Single → `.translatedOnly`, Bilingual → `.interlinear`, language
pick → `setSummaryTargetLanguage`, then `refreshSummaryTranslationIfNeeded()`.
`.originalOnly` is the resting default.

## Round history

| Round | Findings | Resolution |
|---|---|---|
| 1 (`019e9877`) | wiring / isolation / active-segment derivation / overlay dismissal all SOUND. **M1** the summary target language was NOT seeded from the per-book bilingual setting (the host DOES have `book.fingerprintKey` + `PerBookSettings`). **M2** the toggle used SF Symbols instead of the custom `LineGlyph`/`StackGlyph` (Rule-51 fidelity miss). Lows: popover notch missing; the async wiring untested. | see below |
| 2 (`019e987f`) | **clean** — both Mediums resolved; no new Critical/High/Medium; the 2 Lows reasonably accepted. | — |

## Fixes applied

**M1 (per-book seeding)** — `ReaderAICoordinator.setupIfNeeded()` now reads
`PerBookSettingsStore.settings(for: fingerprintKey, baseURL: ReaderContainerView.perBookSettingsBaseURL)`
and seeds `summaryVM.setSummaryTargetLanguage(BilingualLanguage.findOrDefault(key:))`
once at VM creation (language only — no premature translation; `@MainActor`, no
suspension between create + seed, so no race). So the Summarize tab inherits the
book's established bilingual language instead of the global default.

**M2 (custom glyphs)** — NEW `AISummaryLangGlyphs.swift` with `SummaryLineGlyph` /
`SummaryStackGlyph` (custom `Shape` Paths in the design's 16-unit space, the lower
stack pair at 0.55 opacity), matching the artboard `LineGlyph`/`StackGlyph`.
`segmentGlyph` now uses them (the glyph extraction also kept `AISummaryLangRow`
under 300 → 293).

## Accepted Lows (audit-concurred "reasonable")

- **Popover notch/caret** — a fidelity miss vs the artboard's popover pointer, but
  "not a Rule-51 must-fix; the surface is designed, an implementation-detail miss,
  not self-designed UI." The card / 2-col grid / header / footer are faithful.
- **Untested async glue** (`selectDisplayMode`/`selectLanguage`) — thin wiring over
  already-covered pure mappings (`AISummaryLangRowTests`) + VM behavior
  (`AIAssistantViewModelBilingualSummaryTests`). Accepted.

## Rule-51 note (carried from WI-2 implementation)

The artboard toggle is 2-segment Single/Bilingual; `.originalOnly` is the resting
default (no third "Original" widget invented). The audit did NOT flag the
resting-default as a blocker. Whether an explicit "return to original" affordance
is desired is a design-fidelity question for a later pass — WI-3 (card render) may
surface it more concretely. Not invented here (Rule 51).

## Per-book seeding ownership

WI-1's plan made the injection WI-2's job; done in `ReaderAICoordinator` (M1).

## Verdict

`follow-up-recommended`. WI-2 is clean (2 rounds → 0 open Critical/High/Medium; the
2 Lows accepted). 24 tests (LangRow mapping + the WI-1 VM suite) pass. The control
is wired to the VM; WI-3 (the card render of original/target/interlinear + the
dual-skeleton + failure-recovery) is the final WI.
