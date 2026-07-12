---
branch: feat/131-wi7a-compose-ui
threadId: 019f5571-6b9e-7302-a617-92350c23207a
rounds: 3
final_verdict: follow-up-recommended
date: 2026-07-12
---

# Gate-4 audit — feature #131 WI-7a (Android bilingual Compose UI)

Independent Codex review (gpt-5.6-sol, read-only sandbox, reasoning effort high) of the WI-7a
Compose UI slice: the host-neutral `BilingualRenderState` DTO, the TXT/MD interlinear translation
slot (`BilingualInterlinearBody.kt`), the bilingual setup sheet
(`BilingualSetupSheet.kt` + `BilingualSetupSheetParts.kt`), and the top-chrome pill
(`BilingualPill.kt`), plus their connected Compose tests under
`android/app/src/androidTest/kotlin/com/vreader/app/bilingual/`.

Audit foci: fidelity to the committed design bundle (`vreader-bilingual.jsx` +
`vreader-bilingual-offline.jsx`) with NO invented UI (rule 51); the round-4 H2 render contract
(translation as a muted, non-registered `Text` child); Paragraph-only granularity, no Sentence/Style
(round-4 H3); Compose UDF/state-hoisting; recomposition/stability; light+dark; file size; edge cases.

## Round 1 — 3 High, 4 Medium, 1 Low

- **High** — the inline "Couldn't translate" + Retry error slot was INVENTED (the offline bundle
  depicts Retry only in the page-level `BilingualPageBanner`, never a per-slot inline error). **Fixed:**
  the Error phase now renders the DEPICTED ghost slot (`BilingualGhostSlot`: dim 0.33 accent border +
  dashed line, no copy); the page-level Retry is WI-8 chrome (rule 51).
- **High** — the setup sheet did not reproduce the designed `Sheet` chrome (no centered title, no
  divider, non-scrollable body). **Fixed:** centered serif title + bottom rule + a vertically-scrollable
  body (the `TocContentsSheet`/`ReaderSettingsSheet` Android reproduction; `ModalBottomSheet` supplies
  the grabber + scrim-tap dismiss).
- **High** — the translation gesture exclusion via `clearAndSetSemantics {}` did not gate the ancestor
  selection detector's nearest-source-chunk fallback. **Fixed (boundary-correct):** WI-7a keeps the
  translation non-registered; the source-side `hitAt` fallback exclusion is WI-8's contracted
  responsibility (plan §280), documented in code + the HANDOFF.
- **Medium** — language grid fixed-height `LazyVerticalGrid` could clip the last row. **Fixed:** a plain
  `Column`-of-`Row`s, so every tile composes/lays out fully inside the scrolling sheet.
- **Medium** — shimmer read its animated value in composition + wrong copy. **Fixed:** the sweep phase
  is read in the DRAW phase (`drawBehind`) so the slot does not recompose; label is the plan copy
  "Translating chapter… N%".
- **Medium** — all translations forced `VReaderFonts.Serif`. **Fixed:** the translation inherits the
  active source font family and forces serif only for CJK/RTL targets (the design's `translatedFF`).
- **Medium / Low** — weak test assertions + `List` stability note. Test coverage strengthened
  (ordering/bounds, Latin-family inheritance); the DTO carries the same immutable list the VM owns.

## Round 2 — High resolved introduced 1 new High, 1 residual Medium, 1 Low

- **High (regression)** — the consuming `pointerInput` on the translation swallowed drag deltas and
  would block reader `LazyColumn` scroll when a swipe starts on translation text. **Fixed:** the
  consuming `pointerInput` was REMOVED — the translation relies on non-registration only and never
  consumes pointer/drag events (the source-side long-press exclusion stays WI-8's, per plan §280).
- **Medium (residual)** — the sheet uses `theme.background` rather than a dedicated `#fcf8f0`/`#222020`
  sheet-surface token. **Accepted with rationale:** every existing Android designed sheet
  (`TocContentsSheet`, `ReaderSettingsSheet`) uses `theme.background` by the same "render in the active
  theme" convention; a dedicated sheet-surface token is a `ReaderTheme.kt` change OUTSIDE the WI-7a
  write-set — a documented follow-up, not a WI-7a-local change.
- **Low** — stale `Error` KDoc. **Fixed.**

## Round 3 — High + Low confirmed resolved, 2 new Medium (both fixed)

- Confirmed: the scroll High is resolved (no `pointerInput`/click/consume remains on the translation),
  and the `Error` KDoc is corrected. No new Critical/High.
- **Medium** — `clearAndSetSemantics {}` hid the translation from TalkBack. **Fixed:** removed the
  semantics clearing entirely — the translation is a plain accessible muted `Text`; it is "non-registered"
  purely by not being wired into the source-selection `registerChunk` loop (WI-8), NOT by hiding
  semantics.
- **Medium** — no scroll-regression test. **Fixed:** added a connected test that swipes STARTING over
  the translation inside a scrollable `LazyColumn` and asserts the list scrolls (via `LazyListState`),
  guarding against reintroducing a consuming pointer handler.

## Final verdict — follow-up-recommended

No open Critical/High/Medium after round 3, except ONE Medium accepted with rationale (the
sheet-surface color token — a `ReaderTheme.kt` follow-up outside the WI-7a write-set). All other
round-1/2/3 findings resolved with code + connected tests. Connected suites (emulator-5554,
one class per run): `BilingualInterlinearBodyUiTest` 10/10, `BilingualSetupSheetUiTest` 8/8,
`BilingualPillUiTest` 3/3, `BilingualRenderStateDerivationTest` 7/7 — 28 tests, 0 failures.

Follow-ups recorded for the orchestrator: (1) a dedicated reader sheet-surface color token in
`ReaderTheme.kt` (`#fcf8f0`/`#222020`) applied to ALL Android designed sheets; (2) the source-side
long-press gesture-exclusion is owned by WI-8 (`TxtReaderActivity` loop, plan §280), with its own
connected long-press-does-not-select test.

Thread IDs: round 1 `019f555b-f904-7d13-98fa-27aea8821f7e`, round 2 `019f556b-b33a-7a60-ada2-d6cb77d56057`,
round 3 `019f5571-6b9e-7302-a617-92350c23207a`.
