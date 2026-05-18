---
branch: feat/feature-65-wi-3-translate-reskin
threadId: 019e3d53-cdfd-7522-ac63-dfb88c01603c
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Gate-4 implementation audit — feature #65 WI-3 (AI Translate tab-body re-skin)

Independent Codex audit of the `feat/feature-65-wi-3-translate-reskin`
diff against `main`. WI-3 re-skins the AI sheet's Translate tab body to
the visual-identity-v2 design (`vreader-panels.jsx` `TranslateView`):
new `TranslateLanguageRail` (target-language pill rail) and
`TranslationResultCard` (stacked original + accent translation cards),
an additive `theme: ReaderThemeV2 = .paper` parameter on
`TranslationPanel`, in-flight cancellation in `AITranslationViewModel`,
and removal of the pre-v2 `BilingualView`.

## Round 1 — thread 019e3d53

| # | file:line | severity | finding | resolution |
|---|---|---|---|---|
| 1 | TranslationPanel.swift:95 | High | `requestTranslation(_:)` mutated `viewModel.targetLanguage` then launched an unstructured `Task`; `translate` re-read `self.targetLanguage` inside the task. Under rapid pill taps, task scheduling can invert so a request's language is decided by a *later* tap's mutation rather than the tap that spawned it — request identity depended on shared mutable state, and an older task could cancel a newer in-flight request. | **Fixed.** Threaded the tapped language through the async boundary: `AITranslationViewModel.translate` gained a `targetLanguage: String` parameter; it sets `self.targetLanguage` from the parameter (so the rail's selection highlight follows) and passes the parameter to `performTranslation`. The `let targetLanguage = self.targetLanguage` re-read is removed. `TranslationPanel.requestTranslation(_:)` no longer mutates `viewModel.targetLanguage`; it passes the tapped `language` straight into `translate(..., targetLanguage:)`, captured immutably in the spawned `Task`'s closure. |
| 2 | TranslationResultCardTests.swift:57, TranslateLanguageRailTests.swift:118 | Medium | The added UI coverage was largely smoke-only `_ = body` materialization — it would not catch regressions in the `"Original"` label, target-language labeling, CJK font-family switching, or the tap-ordering behaviour. | **Fixed.** `TranslationResultCard.translationFontFamily` extracted to a pure `static func translationFontFamily(for:) -> ReaderFontFamily`; `originalCardLabel` exposed as a `static let`. Added 4 behavioural tests to `TranslationResultCardTests` (CJK → `.system`, non-CJK → `.sourceSerif4`, unknown/empty → `.sourceSerif4`, `originalCardLabel == "Original"`) and a behavioural seam test `translateUsesThePassedLanguageNotTheStaleProperty` to `AITranslationTests` that pre-sets `targetLanguage` to a stale value, calls `translate(..., targetLanguage:)` with a different language, and asserts the provider request carries the *passed* language — directly pinning finding #1 (fails on the pre-fix code). The composition `_ = body` tests are retained as layout-trap guards alongside the new behavioural assertions. |

Round-1 verdict: `follow-up-recommended`. Clean checks: `BilingualView`
fully removed with no orphaned references; no retain cycles in the new
cancellation path; no JS / string-interpolation security surface (pure
SwiftUI); no file-size or actor-isolation violations in the touched
sources.

## Round 2 — codex-reply on 019e3d53

Re-review of the current `git diff main` after the two fixes. Codex
confirmed: the tap-order race is fixed correctly (`TranslationPanel`
passes the tapped language straight into `translate(..., targetLanguage:)`;
`AITranslationViewModel` uses the parameter as the request source of
truth instead of re-reading mutable state); the stale-property
regression test directly pins the old failure mode; the test-quality
finding is addressed with real behavioural assertions for CJK / non-CJK
/ default font-family selection plus the honest `"Original"` label.

Round-2 verdict: **no still-open or newly introduced issues** in the
current `git diff main`.

## Resolution summary

Both findings (1 High, 1 Medium) across 2 rounds are fixed. No open
Critical/High/Medium. Test gate: all Swift Testing suites pass (zero
`✘`); `AITranslationViewModel`, `Translate language rail re-skin`, and
`Translate result card re-skin` suites all green. The full
`xcodebuild test` run reports `** TEST FAILED **` solely from the known
pre-existing `DictionaryLookupTests` (`UIReferenceLibraryViewController`)
host-crash baseline, unrelated to this WI. **Verdict: ship-as-is.**
