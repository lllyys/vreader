# Feature #90 — Bilingual AI summary (Summarize-tab language + single/dual control)

**GH:** #1531 · **Design:** `dev-docs/designs/vreader-fidelity-v1/project/design-notes/bilingual-summarize-90.md` + `bilingual-summarize-artboards.jsx` (landed via #1478).
**Status:** Gate 1 (plan) — 2026-06-05.

## Problem

The Summarize tab produces a single-language summary. Feature #56's bilingual reading is a reading-surface setting, not reachable from Summarize. #90 brings the language choice INTO the Summarize tab: show the summary as the model produced it (**original-only**), **translated** to a target language (target-only), or **interlinear** (both stacked, like the bilingual reading surface) — without leaving the AI sheet. The user asked: "the summarize should be able to bilingual too."

## Model-assumption corrections (verified against code — to confirm at Gate 2)

- **`summarize()` does NOT currently take `targetLanguage`.** Its signature is `summarize(locator:fullText:format:scope:chapterBounds:)` (`AIAssistantViewModel.swift:117`). Only `translate()` takes `targetLanguage` (`:155`). The design note's "summarize already takes targetLanguage" is **stale** — the bilingual mode must add it (or a sibling entry point).
- **The summary is produced via `performAction(type: .summarize, …)`** into `responseText`; state is the `AIAssistantState` enum (`idle/loading/streaming/complete/error/consentRequired/featureDisabled`, `:26`). That enum has **no representation** for "summary landed, translation pending/failed" — the bilingual flow needs a SEPARATE translation sub-state so the summary can ship while its translation is independently loading / failed / done.
- **`AISummaryTabView.swift` is already 393 lines** (over the ~300 guideline). The new language row + the card states will need extraction (a `+Bilingual` / `+LangRow` support file) from the start.
- **Reuse, do not reinvent, the bilingual presentation**: the interlinear stacked render + the muted smaller target style already exist for the Translate-result card / the #56 bilingual reader — mirror that vocabulary (the design says "summary and reading surface feel like one mode").

## Surface area (file-by-file)

### MODIFY `vreader/ViewModels/AIAssistantViewModel.swift` (+ a new `+BilingualSummary.swift` extension)
- **Display mode is a 3-way ENUM of CONCRETE OBSERVABLE OUTPUTS (Gate-2 H1 r2)**: `enum SummaryDisplayMode: Sendable { case originalOnly, translatedOnly, interlinear }`. The codebase has NO "reader's language" / source-language authority (summarize carries no language param — `AIProvider.swift:174-197`; the bilingual surface hardcodes "EN" as a placeholder — `BilingualPill.swift:23`), so the modes are framed by what is actually OBSERVABLE: `.originalOnly` = the summary EXACTLY as the model produced it (no translation — today's behavior, the default); `.translatedOnly` = translate that summary → the target `BilingualLanguage`, show ONLY the translation; `.interlinear` = show BOTH (original ¶ + translated ¶ stacked). The VM holds `private(set) var summaryDisplayMode: SummaryDisplayMode = .originalOnly`. **Control mapping (WI-2, grounded in the artboards)**: the control sets the 3-output enum DIRECTLY — the landed "Single · source" / "Single · target" / "Bilingual" states map 1:1 to `.originalOnly` / `.translatedOnly` / `.interlinear` (no "reader-language" comparison; see the WI-2 `AISummaryLangRow` entry). `.originalOnly` is the default and needs NO translation; the other two run the translation step (differing only in RENDER).
- **Language authority is `BilingualLanguage` (Gate-2 M1)**: `summaryTargetLanguage: BilingualLanguage`, defaulting to the **per-book `PerBookSettings.bilingualTargetLanguage`** the bilingual reader persists (`PerBookSettings.swift:31`, `BilingualReadingViewModel.swift:148`, `BilingualLanguage.all` — Italian + glyph/script metadata). Do NOT reuse Translate's in-memory `"Chinese"` string. The popover lists `BilingualLanguage.all`.
- **Injection ownership (Gate-2 r2 Medium)**: `AIAssistantViewModel` is currently constructed with only `aiService` (`ReaderAICoordinator.swift:252`) — it has no `bookFingerprintKey` / per-book-settings access. The reader HOST resolves the per-book `bilingualTargetLanguage` default and passes it into the summary surface (the cleanest: the host resolves a `BilingualLanguage` and seeds `setSummaryTargetLanguage` once on first appear; do NOT widen the VM's constructor to take persistence). Tests cover saved-key / missing-key / stale-key fallback (→ a sensible default like the first `BilingualLanguage.all`).
- **Setters are SYNCHRONOUS pure mutators (Gate-2 critique)**: `setSummaryDisplayMode(_:)` / `setSummaryTargetLanguage(_:)` only mutate state (mirror `setScope`); they do NOT run async work. A SEPARATE `async` method (`refreshSummaryTranslationIfNeeded()`) is what kicks the (re)translation, called by the view on the relevant change.
- **A dedicated PRIVATE summary-translation helper (Gate-2 M2)** — do NOT route through public `translate()` / `performAction()` (those expect reader doc text + a locator, and `performAction` CLEARS `responseText` + rewrites `state`/`currentAction`, which would destroy the summary). The helper calls `aiService.sendRequest` with a `.translate` action and the GENERATED SUMMARY TEXT (`responseText`) as the input, storing the result ONLY in `summaryTranslation` — never touching `responseText`/`state`.
- Translation sub-state: `enum SummaryTranslationState: Sendable, Equatable { case none, translating, translated(String), failed }` + `private(set) var summaryTranslation`. A failure leaves the summary intact → `.failed` (recovery). `retrySummaryTranslation()` re-runs ONLY the translation half.
- **The translation half has its OWN cancellable task + op-token (Gate-2 M3 + R1)**: a re-summarize / display-mode flip / language change cancels the in-flight translation (cooperative-cancel + token guards, the #87 pattern) and resets `summaryTranslation`; a cancelled translation must not clobber a newer one. Stop affordance: the translation phase (summary landed, translation `.translating`) is cancellable — WI-3's dual-skeleton/translation-loading state carries a Stop/cancel, since the existing tab-level Stop only fires in `state == .loading` and would not cover the second step.
- **Shared teardown (Gate-2 r2 Medium)**: the existing `reset()` cancels only `streamTask` (`AIAssistantViewModel.swift:204`). A summary-translation task could outlive `reset()` / sheet dismiss and later write STALE bilingual state. Add a `cancelSummaryTranslation()` that cancels the translation task + clears `summaryTranslation`, and call it from `reset()` AND any sheet-teardown path. Test reset/dismiss WHILE translating (no stale write).

### NEW `vreader/Views/Reader/AISummaryLangRow.swift`
- `AISummaryLangRow` — the second control row beneath the scope chips: LEFT a language control (current `BilingualLanguage` target + globe → opens the language popover), RIGHT a segmented toggle. Per the `LangRow` artboard. Themed `ReaderThemeV2`. **Control → mode mapping (Gate-2 H1 r3, grounded in the artboards `:273-278`)**: the landed design has THREE concrete states while the language control is engaged — "Single · source", "Single · target", "Bilingual" — which map **1:1** to `SummaryDisplayMode`: source-only → `.originalOnly`, target-only → `.translatedOnly`, bilingual → `.interlinear`. The control therefore exposes an explicit **source ↔ target** choice for the single case plus the bilingual option (a 3-way selector or a single/dual toggle + a source/target sub-pick — match the artboard at implementation); there is NO "reader-language" comparison. The VM contract is the 3-output enum, set DIRECTLY by the control.

### NEW `vreader/Views/Reader/AISummaryLangPopover.swift`
- `AISummaryLangPopover` — the language list popover over **`BilingualLanguage.all`** (the bilingual authority — Italian + glyph/script metadata; Gate-2 M1), NOT Translate's in-memory string list. Per the `LangPopover` artboard.

### MODIFY `vreader/Views/Reader/AISummaryCard.swift` (+ states)
- Render the three `SummaryDisplayMode` outputs: **single** (`responseText`), **targetOnly** (`summaryTranslation`'s translated text), **interlinear** (source paragraph + target paragraph stacked in the muted smaller bilingual style — reuse the `TranslationResultCard` / #56 vocabulary, which exists as renderer/JS pipelines, NOT a drop-in card, so the card composes the stacked layout itself). The **dual-skeleton** loading (`SummarySkeleton dual`) shows while either half is pending so the layout does not jump, with a Stop/cancel for the translation phase (Gate-2 M3). The **failure-recovery** card (`SummaryError`) shows **"Retry translation" / "Keep original"** (NOT "Keep English" — the source language is unknown; matches `TranslationResultCard`'s generic "Original", Gate-2 M4) when `summaryTranslation == .failed` — the summary still renders above it.

### MODIFY `vreader/Views/Reader/AISummaryTabView.swift`
- Insert `AISummaryLangRow` beneath `AISummaryScopeChipStrip`; present the language popover; pass the dual mode + translation state into `AISummaryCard`. Extract the state-body / card wiring into a `+Bilingual` support file to land under ~300.

### Files OUT of scope
- The Translate tab, the bilingual READING surface (#56) — unchanged; #90 only reuses their presentation vocabulary + language list.
- The scope chips (#69) — unchanged (scope = "how much", language = "in what language"; separate rows).
- The summarization PROMPT / scope extraction — unchanged; the target-language step is a TRANSLATION of the produced summary, not a re-prompt.

## Prior art / precedent / rejected alternatives

- **Precedent**: `translate()` + the Translate-result interlinear card; the #56 bilingual reader's stacked muted-target style; `selectedScope`/`setScope` (the mutator pattern); the #87 cooperative-cancel guards.
- **Rejected — single-prompt "summarize in both languages"**: a model can drift / refuse / mix languages unpredictably; the design's two-step (summarize, THEN translate the summary) is deterministic, lets the summary ship even if translation fails, and reuses the proven translate path. Adopted.
- **Rejected — crowding language into the scope row**: the design explicitly separates them (a `CrowdedRowScreen` rejected artboard exists).

## Work items

| WI | Scope | Tier | PR size |
|---|---|---|---|
| **WI-1** | VM bilingual-summary state + the two-step generation + translation sub-state + retry/cancel guards | behavioral (logic-heavy, highly testable) | ~M |
| **WI-2** | `AISummaryLangRow` + `AISummaryLangPopover` + the TabView wiring (mode/lang control) | behavioral | ~M |
| **WI-3** | `AISummaryCard` render (single / target-only / interlinear) + dual-skeleton + failure-recovery; final → DONE | behavioral (final) | ~M |

## Test catalogue

- **VM (WI-1)** `AIAssistantViewModelBilingualSummaryTests`: `.originalOnly` mode → no translation (`responseText` only, `state` untouched); `.translatedOnly`/`.interlinear` → after summary completes, translation kicks via the PRIVATE helper (NOT performAction — assert `responseText`/`state` are NOT clobbered); translation success → `.translated`; failure → `.failed` + summary text preserved; `retrySummaryTranslation` re-runs only the translation; re-summarize / display-mode flip / language change cancels + resets `summaryTranslation`; the cooperative-cancel race (a cancelled translation does not clobber a newer one — op-token); `cancelSummaryTranslation()` from `reset()` during translation leaves no stale write; the control → `SummaryDisplayMode` mapping (source/target/bilingual → the 3 enum cases) is a pure function — tested.
- **UI derivations (WI-2/3)** pure-pinnable: the card mode selector (single/target/interlinear/skeleton/error) from `(dualMode, state, summaryTranslation)`; the lang-row active-segment; the popover language-list mapping.

## Risks + mitigations

- **R1 — the two-step async race** (re-summarize / mode-flip / lang-change mid-translation): the #87 cooperative-cancel + op-token pattern; reset `summaryTranslation` on every new summary/translation kick. Test the races.
- **R2 — `AISummaryTabView` 393 → over 300**: extract from the start (`+Bilingual` support file).
- **R3 — interlinear paragraph alignment**: the summary is short prose; align by paragraph (source ¶ then target ¶), reusing the bilingual stacked style; a partial translation falls back to source-only for the unmatched tail (the #56 silent-source-fallback precedent).
- **R4 — language default**: source the default target from the existing bilingual/Translate language pref so it is consistent across surfaces.

## Backward compat

Pure additive: default `summaryDualMode = false` reproduces today's single-language summary exactly. No persistence/schema change (the mode + language are session UI state; optionally persisted to the per-book/bilingual pref in a follow-up). Providers without translation degrade to single (the failure-recovery path).

## Acceptance criteria

1. The Summarize tab shows a language control + a single/dual toggle beneath the scope chips.
2. **Original-only** mode = today's behavior (the summary exactly as the model produced it, no translation).
3. **Bilingual** mode produces the summary THEN translates it; the card renders interlinear (source + target stacked, muted target style); a dual-skeleton shows while loading (no layout jump).
4. If translation fails, the summary still ships; the card offers "Retry translation" / "Keep original"; Retry re-runs only the translation. The translation phase is cancellable (Stop).
5. Changing the target language re-translates (or invalidates) the bilingual output.
6. Scope (#69) and the bilingual control compose (any scope × single/dual); no regression to the single-language summary, the Chat/Translate tabs, or Stop control.

## Revision history / Audit fixes applied

- **Gate-2 round 1** (Codex `019e983b`, verdict NEEDS REVISION — 1 High + 4 Medium):
  - **H1** a Boolean `summaryDualMode` cannot select `target-only` → replaced with `enum SummaryDisplayMode { single, targetOnly, interlinear }`, derived from the `(single/dual toggle, language)` controls.
  - **M1** no shared language pref exists → authority is `BilingualLanguage.all` + the per-book `bilingualTargetLanguage` (Italian + glyph metadata); dropped the Translate-pref assumption.
  - **M2** the 2nd-step translate cannot reuse public `translate()`/`performAction()` (clears `responseText` + rewrites `state`) → a dedicated PRIVATE helper via `aiService.sendRequest(.translate)` storing only in `summaryTranslation`.
  - **M3** Stop only fires in `state == .loading`; the translation phase had no Stop → the translation half has its own cancellable task + a translation-phase Stop in the card.
  - **M4** "Keep English" is wrong (source language unknown) → "Keep original" (matches `TranslationResultCard`).
  - **Critique** keep `setSummaryDisplayMode`/`setSummaryTargetLanguage` synchronous; a separate `async refreshSummaryTranslationIfNeeded()` triggers the (re)translation.
- **Gate-2 round 2** (Codex `019e9842` — M2/M4/critique confirmed resolved; 1 High + 2 Medium remained):
  - **H1 (still)** the 3-way enum kept a "reader's language" authority that does not exist → reframed to CONCRETE OBSERVABLE outputs `originalOnly / translatedOnly / interlinear` (no reader-language authority; the summary as produced IS "original"). Toggle↔mode mapping flagged for Rule-51 confirm at WI-2.
  - **Medium (injection)** the VM has no per-book-settings access → the reader host resolves the per-book `bilingualTargetLanguage` default + seeds it into the summary surface (no constructor widening); saved/missing/stale-key tests.
  - **Medium (teardown)** a translation task could outlive `reset()` → added `cancelSummaryTranslation()` called from `reset()` + sheet teardown; reset-while-translating test.
- **Gate-2 round 3** (Codex `019e9849` — injection + teardown Mediums confirmed resolved; the H1 reframe was correct in the VM core but STALE "reader-language" wording lingered in WI-2/tests/acceptance). **Resolution (per the auditor's exact prescription, verified against the artboards `:273-278`)**: the design has three concrete states — "Single · source", "Single · target", "Bilingual" — mapping 1:1 to `originalOnly`/`translatedOnly`/`interlinear`; scrubbed the residual "reader-language" wording from the Problem, the VM control-mapping, WI-2, the test catalogue, and acceptance. The 3-round cap is reached; this is an `accept`-the-prescribed-fix resolution (a targeted mode-model redesign to grounded observable outputs), not a genuine impasse — the plan is now internally consistent + grounded for implementation. The only implementation-time open item is the Rule-51 confirm of the exact `LangRow` control WIDGET (3-way selector vs toggle+sub-pick) against the canvas at WI-2 — a normal design-fidelity check, not a plan blocker.
