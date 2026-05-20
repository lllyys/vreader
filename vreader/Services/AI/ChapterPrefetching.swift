// Purpose: Feature #56 WI-7b — the translation-prefetch seam the
// `BilingualReadingViewModel` depends on. The VM's unit-aware prefetch trigger
// must fetch "the translated segments for unit X" without knowing about
// provider resolution, the disk cache, chunking, or `AIService`. This
// protocol is that seam: tests inject a deterministic mock; production wires a
// thin adapter over `ChapterTranslationService` + `AIService`.
//
// Key decisions:
// - `Sendable` so the VM can hold an `any ChapterPrefetching` and call it from
//   detached prefetch `Task`s.
// - The result is the ordered translated segments (`[String]`), one per source
//   paragraph/sentence — exactly what the VM stores in `translationsByUnit`.
// - Failure surfaces as the existing `ChapterTranslationError`: `.offline`
//   drives the silent-source-fallback (plan Decision 2 — no invented
//   affordance), `.cancelled` is swallowed by the epoch guard, other failures
//   leave the unit unfetched so a later position change retries.
//
// @coordinates-with: BilingualReadingViewModel.swift,
//   ChapterTranslationService.swift, ChapterTextProviding.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-7b)

import Foundation

/// Supplies the translated segments for one translation unit — the seam the
/// bilingual view model's prefetch trigger calls.
protocol ChapterPrefetching: Sendable {
    /// Translates `unit` into `targetLanguage` and returns the ordered
    /// translated segments (one per source paragraph/sentence). Throws
    /// `ChapterTranslationError` — `.offline` when the device is offline and
    /// the unit is not cached, `.cancelled` when the task was cancelled,
    /// `.providerFailed` on a network / API error.
    func translatedSegments(
        for unit: TranslationUnitID,
        targetLanguage: String,
        granularity: TranslationGranularity
    ) async throws -> [String]
}
