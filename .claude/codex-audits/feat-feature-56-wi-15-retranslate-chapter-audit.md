---
branch: feat/feature-56-wi-15-retranslate-chapter
threadId: 019e4399-b8cd-7653-89f3-26b9618a40da
rounds: 1
final_verdict: ship-as-is
date: 2026-05-20
---

# Feature #56 WI-15 — Gate-4 implementation audit

Single-round Codex audit (read-only sandbox), `019e4399-b8cd-7653-89f3-26b9618a40da`.

## Scope

Per-chapter re-translation (final WI of feature #56). Covers:

- `ChapterReTranslateViewModel` + `ChapterReTranslateBoundaries`
- `ReTranslatePickerSheet` / `ReTranslatePickerSheetParts` / `ReTranslateProgress` / `ReTranslateFlowLayout`
- `ReaderContainerView+ReTranslate` host wiring + the `ReaderReTranslateObserver` modifier
- `.readerBilingualReTranslateApplied` notification + observer additions in each per-format `+Bilingual` modifier (EPUB/TXT/MD/PDF) and inline in `FoliateBilingualContainerView`
- `BilingualReadingViewModel.applyReTranslateResult` (host-callback target)
- `ChapterReTranslateViewModelTests` (Swift Testing, 11 cases)

## Round 1 findings

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `ReaderContainerView+ReTranslate.swift:154` | Critical | `sourceTextProvider` collapsed all `sourceText(for:)` failures (including `CancellationError`) to empty string; the VM's empty-source branch then posted `[]` back into the bilingual VM and ended in `.complete`, while having ALREADY deleted the original cache row. A real source-text extraction error would surface as a misleading "Re-translated" success state. | **FIXED**. Signature changed to `@Sendable (TranslationUnitID) async throws -> String`. `runSubmit` now handles three outcomes: empty string → legitimate empty unit complete; `CancellationError` → cancel path, no apply, return to picker; any other error → set `lastError`, route to `.picker`. Two new tests cover the throwing + cancellation branches. |
| `BookTranslationCoordinator.swift:186` (cross-file) | Medium | The whole-book translation coordinator and the WI-15 manual re-translate can target the same `(book, unit)` concurrently. When they collide on the same lookup key, last-cache-write wins — a background whole-book job that completes after the manual re-translate could overwrite the user's freshly re-translated chapter. | **ACCEPTED with rationale**. The plan's edge case (f) explicitly chose this behavior: "concurrent global translation + single-chapter re-translate racing on the same chapter — last writer wins, or serialise via actor". The chosen design is last-writer-wins via `ChapterTranslationStore`'s idempotent upsert (also documented in `BookTranslationCoordinator.swift` row 279 of the plan). Adding a unit-level lock would conflict with the plan's accepted trade-off. Audited cross-feature `BookTranslationCoordinator` source for unintended damage paths: store is the only shared mutation point; corruption is not possible (each `upsert` is atomic on `lookupKey`); only the temporal-ordering question remains, and the plan accepted it. |
| `ReaderContainerView+ReTranslate.swift:114` | Low | A reused VM's previous picker selection may reference a `providerProfileID` that's been deleted between picker opens. The submit path fails only after the user taps "Re-translate" because the resolver can't find the profile. | **FIXED**. On every `handleReTranslateChapterRequested()` the host now checks `vm.selection.providerProfileID` against the fresh snapshot and resets it to `activeOrFirstProfile.id` + its model when stale, BEFORE calling `presentPicker(...)`. |

## Security

No findings. The diff is pure Swift (no JS injection surface). Provider credentials flow only through `ResolvedAIProviderConfig`, which is built by `AIService.config(from:)` and never crosses an untrusted boundary. The picker's selection never mutates `ProviderProfileStore`'s active id — acceptance criterion (f) is satisfied (audited the resolver path; no `setActiveProfileID` reachable from the WI-15 code).

## Cache-delete behavior under provider override

Audited the "delete original lookup-key when overriding to a different provider" semantic. The original key is deleted unconditionally; if the picker overrides to a DIFFERENT profile, the original-profile cache row is removed and the new row writes under the override-profile lookup key. The Codex auditor explicitly evaluated this and did NOT flag it — it matches the documented "clear old cache and fetch fresh" intent (acceptance criterion (e)). A future user who flips back to the original profile after a re-translate-with-override will trigger a fresh prefetch on the original-profile key, which is the correct behavior.

## Verdict

**ship-as-is**. All Critical/Medium/Low findings resolved or accepted with rationale. Tests cover the new branches.
