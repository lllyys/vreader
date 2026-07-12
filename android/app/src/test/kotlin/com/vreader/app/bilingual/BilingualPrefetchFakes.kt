// Purpose: feature #131 WI-6 — shared test fakes for the BilingualViewModel position-driven
// prefetch tests (kept out of the test classes so both the behavioral suite and the
// concurrency-decisive suite share one controllable seam without duplicating it, and so each
// test file stays under the ~300-line bar). NOT production code (test source set only).
package com.vreader.app.bilingual

import kotlinx.coroutines.CompletableDeferred

/** A [ChapterTextProvider] whose current unit + ordering the test drives. */
class FakeTextProvider : ChapterTextProvider {
    var units: List<TranslationUnitId> = emptyList()
    var containing: TranslationUnitId? = null

    override fun units(): List<TranslationUnitId> = units
    override fun sourceSegments(unit: TranslationUnitId): List<String> = listOf("src of ${unit.value}")
    override fun sourceText(unit: TranslationUnitId): String = "src of ${unit.value}"
    override fun unitContaining(charOffsetUtf16: Int): TranslationUnitId? = containing
    override fun unitAfter(unit: TranslationUnitId): TranslationUnitId? {
        val i = units.indexOf(unit)
        return if (i in 0 until units.size - 1) units[i + 1] else null
    }
}

/**
 * A controllable [BilingualPrefetching] seam: primes per-unit outcomes (typed error /
 * gated-in-flight) and records both every attempt and every COMPLETED write, so a test can
 * assert single-flight (exactly one write) + stale-discard + failure mapping.
 */
class FakePrefetching : BilingualPrefetching {
    /** Units whose prefetch should throw a typed error (never completing a write). */
    val throwTyped = mutableMapOf<TranslationUnitId, ChapterTranslationError>()
    /** Units whose prefetch should throw a RAW (non-typed) throwable — the "unexpected" path. */
    val raw = mutableMapOf<TranslationUnitId, Throwable>()
    /** Units whose prefetch should suspend until the deferred completes (in-flight control). */
    val pending = mutableMapOf<TranslationUnitId, CompletableDeferred<Unit>>()
    /** Every prefetch(unit) invocation, in order (records attempts, incl. superseded/cancelled). */
    val prefetchInvocations = mutableListOf<TranslationUnitId>()
    /** Count of COMPLETED writes per unit (a successful return that produced a result). */
    val completed = mutableMapOf<TranslationUnitId, Int>()

    override suspend fun prefetch(
        unit: TranslationUnitId,
        targetLanguage: String,
        granularity: TranslationGranularity,
    ): ChapterTranslationResult {
        prefetchInvocations.add(unit)
        pending[unit]?.await()   // may throw CancellationException if the caller's job is cancelled
        throwTyped[unit]?.let { throw ChapterTranslationException(it) }
        raw[unit]?.let { throw it }
        completed[unit] = (completed[unit] ?: 0) + 1
        return ChapterTranslationResult(segments = listOf("译文 of ${unit.value}"), fromCache = false)
    }
}
