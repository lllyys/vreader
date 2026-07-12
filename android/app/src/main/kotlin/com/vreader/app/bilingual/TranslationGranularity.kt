// Purpose: feature #131 WI-1 — the translation segmentation granularity for
// bilingual reading (design §2.2). Both cases are defined; the v1 Android render
// uses only `paragraph` (`sentence` is reserved-foundational, wired for a later
// WI but not yet used by the render path).
//
// @coordinates-with: ChapterSegmenter.kt,
//   dev-docs/plans/20260710-feature-131-android-bilingual.md (WI-1)
package com.vreader.app.bilingual

/** Whether a chapter is segmented into paragraphs or sentences for translation. */
enum class TranslationGranularity {
    paragraph,
    sentence,
}
