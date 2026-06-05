---
branch: feat/feature-90-wi-3-card
threadId: 019e988e-d0f5-74c2-8fff-ca61fbbe19b2
rounds: 2
final_verdict: follow-up-recommended
date: 2026-06-06
---

# Gate-4 audit — Feature #90 WI-3 (bilingual AISummaryCard render — FINAL WI)

WI-3 renders the Summarize card body in the three `SummaryDisplayMode` outputs
(original-only / target-only / interlinear) plus the dual loading skeleton and
the translation-failure recovery card, driving off the WI-1 VM
(`summaryDisplayMode` / `summaryTranslation` / `retrySummaryTranslation` /
`setSummaryDisplayMode`). Pure body-mode selector `AISummaryCardBody.resolve`,
`AISummarySkeleton`, `AISummaryErrorCard`. Mirrors the committed artboards
`bilingual-summarize-artboards.jsx` `SummaryCard` / `SummarySkeleton` /
`SummaryError`; the failure button is "Keep original" (NOT the artboard's "Keep
English") per the WI-1 Gate-2 M4 ruling (source language unknown).

## Round history

| Round | threadId | Findings | Resolution |
|---|---|---|---|
| 1 | `019e988e` | **2 High, 1 Medium, 1 Low.** **H1** `AISummarySkeleton` clamped to a fixed `.frame(height: 60/110)` inside a `GeometryReader`-as-parent → clips the bars (true height ~78 single / ~130 dual). **H2** `runSummarize()` never re-kicked the translation after `summarize()`; since `performAction` resets translation to `.none` and the selector maps `(translatedOnly\|interlinear, .none) → .original`, a fresh/regenerated summary with Single/Bilingual pre-selected fell back to original-only until re-toggled. **M** the selector tests pin the matrix but not the render contract (`.translated` extraction / CJK-font branch could break and pass). **L** `AISummaryTabView` 422 lines (pre-existing WI-2 overage). | all fixed → round 2 |
| 2 | `019e989a` | round-1 four **all resolved**; **1 new Medium** — the DEBUG-only DebugBridge summarize path (`AIReaderPanel+DebugBridgeAIAction.swift:107`) had the SAME drift as H2 (no `refreshSummaryTranslationIfNeeded()` after `summarize`), so `ai?action=summarize` with a bilingual mode selected would render original-only (also the CU-free Gate-5 path). | fixed (mirror) — no open Critical/High/Medium |

## Fixes applied

- **H1 (skeleton clip)** — removed the fixed-height wrapper. `AISummarySkeleton`
  now lays out a plain `VStack` (height content-driven) and reads its width via a
  background `GeometryReader` → `SummarySkeletonWidthKey` `PreferenceKey` →
  `onPreferenceChange(availableWidth)`. Each bar is an `HStack` of a
  `fraction × availableWidth` rect + a trailing `Spacer`, preserving the design's
  percentage widths with no `GeometryReader`-as-parent. Round-2 confirmed no
  layout loop / greedy fill / persistent zero-width.
- **H2 (post-summarize translate)** — `runSummarize()` now awaits
  `summarize(...)` then `refreshSummaryTranslationIfNeeded()` (no-op for
  `.originalOnly`; the WI-1 op-token guard drops a superseded result).
- **M (render-contract coverage)** — extracted
  `AISummaryCardBody.translatedText(from:)` + `AISummaryCardBody.usesCJKFont(for:)`
  as pure statics; the card delegates to them. Added
  `translatedTextExtractsOnlyFromTranslated` + `cjkScriptSelectsTheCJKFont` tests
  (13 tests total). The remaining visual states (skeleton sizing, retry/keep
  wiring) are covered by Gate-5 UI verification per the audit's allowance.
- **L (file size)** — extracted the idle/loading/error/feature-disabled/
  consent-required/`infoState` sections + `errorMessage`/`chipFillColor` into
  `AISummaryTabView+Sections.swift` (`internal` members; `stateBody` still routes
  all 6). Base 245 lines, extension 213 — both under ~300.
- **Round-2 M (DebugBridge drift)** — mirrored the H2 fix into the DEBUG-only
  `AIReaderPanel+DebugBridgeAIAction.swift` summarize case (await
  `refreshSummaryTranslationIfNeeded()` after `summarize`), so the bridge path
  matches production and the CU-free Gate-5 `ai?action=summarize` verification
  exercises the bilingual mode.

## Verdict

`follow-up-recommended`. Two rounds → zero open Critical/High/Medium; the round-2
DebugBridge Medium is fixed by an identical mirror of the round-1-verified
production fix. 13 tests green (`AISummaryCardModeTests`), smoke build SUCCEEDED.
The visual render states (skeleton sizing, retry/keep wiring, CJK rendering)
move to Gate-5 UI verification — WI-3 completes feature #90.
