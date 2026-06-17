package vreader.contracts

import kotlinx.serialization.Serializable

/** Validation failures for [Locator] field values — mirrors Swift `LocatorValidationError`. */
enum class LocatorValidationError {
    negativePageIndex,
    negativeUTF16Offset,
    invertedUTF16Range,
    nonFiniteProgression,
}

/**
 * Engine-neutral reading position within a book — the Kotlin value type that
 * mirrors Swift `Locator` (vreader/Models/Locator.swift). Carries the book
 * identity triple (`contentSHA256`/`fileByteCount`/`format`) plus the per-format
 * position fields; format determines which fields apply (EPUB = href+progression
 * +cfi, PDF = page, TXT = UTF-16 offsets). All position fields are optional.
 *
 * This is the **canonical** half of the persisted `VReaderLocator` envelope — it
 * is what survives an engine swap / cross-device restore. `canonicalJson()` /
 * `fingerprintKey` delegate to the existing [CanonicalLocator] / [Identity]
 * references so there is ONE serialization contract, asserted by the conformance
 * lane.
 */
@Serializable
data class Locator(
    val contentSHA256: String,
    val fileByteCount: Long,
    val format: String,
    val href: String? = null,
    val progression: Double? = null,
    val totalProgression: Double? = null,
    val page: Int? = null,
    val charOffsetUTF16: Int? = null,
    val charRangeStartUTF16: Int? = null,
    val charRangeEndUTF16: Int? = null,
    val cfi: String? = null,
    val textQuote: String? = null,
    val textContextBefore: String? = null,
    val textContextAfter: String? = null,
) {
    /** The book identity key this locator points into (= DocumentFingerprint.canonicalKey). */
    val fingerprintKey: String
        get() = Identity.canonicalKey(format, contentSHA256, fileByteCount)

    /**
     * Validates field values — byte-for-byte the same contract as Swift
     * `Locator.validate()`: non-negative page/offsets, both range endpoints present
     * together with start <= end, finite progressions. Returns null when valid.
     */
    fun validate(): LocatorValidationError? {
        page?.let { if (it < 0) return LocatorValidationError.negativePageIndex }
        charOffsetUTF16?.let { if (it < 0) return LocatorValidationError.negativeUTF16Offset }
        charRangeStartUTF16?.let { if (it < 0) return LocatorValidationError.negativeUTF16Offset }
        charRangeEndUTF16?.let { if (it < 0) return LocatorValidationError.negativeUTF16Offset }
        // Both range endpoints together or neither.
        if ((charRangeStartUTF16 != null) != (charRangeEndUTF16 != null)) {
            return LocatorValidationError.invertedUTF16Range
        }
        val start = charRangeStartUTF16
        val end = charRangeEndUTF16
        if (start != null && end != null && start > end) return LocatorValidationError.invertedUTF16Range
        progression?.let { if (!it.isFinite()) return LocatorValidationError.nonFiniteProgression }
        totalProgression?.let { if (!it.isFinite()) return LocatorValidationError.nonFiniteProgression }
        return null
    }

    /** This locator if valid, else null — the Kotlin form of Swift `Locator.validated(...)`. */
    fun validatedOrNull(): Locator? = if (validate() == null) this else null

    /**
     * Nulls a non-finite progression/totalProgression so an invalid input is stored
     * as a valid locator rather than re-introducing the canonicalize collision —
     * mirrors iOS `Locator.repairedForCanonicalization()` (feature #109 WI-2), the
     * persistence-boundary repair. Structural invalidity (negative/inverted) is NOT
     * repaired (it can't be silently fixed); the caller rejects those.
     */
    fun repairedForCanonicalization(): Locator {
        val progNonFinite = progression?.isFinite() == false
        val totalNonFinite = totalProgression?.isFinite() == false
        if (!progNonFinite && !totalNonFinite) return this
        return copy(
            progression = progression?.takeIf { it.isFinite() },
            totalProgression = totalProgression?.takeIf { it.isFinite() },
        )
    }

    /**
     * Engine-neutral canonical JSON — delegates to [CanonicalLocator] (the single
     * cross-platform serialization contract). Rejects a non-finite progression
     * (mirrors Swift `Locator.validate()`; bug #356).
     */
    fun canonicalJson(): String = CanonicalLocator.canonicalJson(
        contentSHA256 = contentSHA256,
        fileByteCount = fileByteCount,
        format = format,
        cfi = cfi,
        charOffsetUTF16 = charOffsetUTF16,
        charRangeEndUTF16 = charRangeEndUTF16,
        charRangeStartUTF16 = charRangeStartUTF16,
        href = href,
        page = page,
        progression = progression,
        textContextAfter = textContextAfter,
        textContextBefore = textContextBefore,
        textQuote = textQuote,
        totalProgression = totalProgression,
    )
}
