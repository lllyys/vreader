// Purpose: Bridge between Readium's own Locator JSON and vreader's engine-neutral
// VReaderLocator envelope — feature #106 WI-6 (Gate-2 Critical resume). Consumes the
// DOCUMENTED Readium Locator JSON shape (href + locations.progression/
// totalProgression + text.before/highlight/after), so it carries NO Readium
// dependency and is pure-JVM testable. The (design-blocked, #1745) reader host will
// convert Readium's `Locator` <-> JSON via Readium's own toJSON()/fromJSON() and hand
// the string to this bridge; the bridge keeps the verbatim JSON for precise restore
// AND derives a canonical fallback Locator for cross-platform/degraded resume.
package com.vreader.app.reader

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import vreader.contracts.BookFormat
import vreader.contracts.Locator
import vreader.contracts.ReaderLocatorEngine
import vreader.contracts.VReaderLocator

/** A Readium Locator JSON string could not be decoded (blank / malformed / corrupt). */
class ReaderLocatorParseException(message: String, cause: Throwable? = null) : Exception(message, cause)

/** The minimal slice of Readium's Locator JSON the resume contract needs. */
@Serializable
private data class ReadiumLocatorDto(
    val href: String? = null,
    val locations: Locations? = null,
    val text: Text? = null,
) {
    @Serializable
    data class Locations(
        val progression: Double? = null,
        val totalProgression: Double? = null,
        val position: Int? = null,
    )

    @Serializable
    data class Text(
        val before: String? = null,
        val highlight: String? = null,
        val after: String? = null,
    )
}

/**
 * Converts between a Readium Locator JSON string and the [VReaderLocator] envelope.
 * The [bookContentSHA256]/[bookFileByteCount]/[bookFormat] triple supplies the book
 * identity Readium's locator omits (it only describes a position WITHIN a known book).
 */
class ReadiumLocatorBridge(
    private val json: Json = DEFAULT_JSON,
) {
    /**
     * Wraps a Readium Locator JSON string as a `readium`-engine [VReaderLocator]:
     * keeps the verbatim JSON for precise on-device restore AND derives a canonical
     * fallback [Locator] (href + progression + text-quote) for degraded/cross-platform
     * resume. A non-finite progression in the Readium JSON is dropped from the fallback
     * (it would make the canonical locator invalid).
     */
    fun toEnvelope(
        readiumLocatorJSON: String,
        bookContentSHA256: String,
        bookFileByteCount: Long,
        bookFormat: BookFormat,
    ): VReaderLocator {
        // Defined degraded behavior for corrupt upstream input: a typed failure the
        // caller can catch (never a raw SerializationException out of the bridge).
        val dto = try {
            json.decodeFromString<ReadiumLocatorDto>(readiumLocatorJSON)
        } catch (e: Exception) {
            throw ReaderLocatorParseException("malformed Readium Locator JSON", e)
        }
        val fallback = Locator(
            contentSHA256 = bookContentSHA256,
            fileByteCount = bookFileByteCount,
            format = bookFormat.name,
            href = dto.href,
            progression = dto.locations?.progression?.takeIf { it.isFinite() },
            totalProgression = dto.locations?.totalProgression?.takeIf { it.isFinite() },
            textQuote = dto.text?.highlight,
            textContextBefore = dto.text?.before,
            textContextAfter = dto.text?.after,
        )
        return VReaderLocator(
            fingerprintKey = fallback.fingerprintKey,
            originalFormat = bookFormat,
            engine = ReaderLocatorEngine.readium,
            readiumLocatorJSON = readiumLocatorJSON,
            legacyLocator = fallback,
        )
    }

    /**
     * The verbatim Readium Locator JSON to feed back to the navigator for a PRECISE
     * restore, or null when the envelope has no Readium locator (a legacy-engine
     * position → the caller uses the canonical fallback instead).
     */
    fun readiumLocatorJSON(envelope: VReaderLocator): String? =
        envelope.readiumLocatorJSON
            ?.takeIf { it.isNotBlank() && envelope.engine == ReaderLocatorEngine.readium }

    companion object {
        private val DEFAULT_JSON = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    }
}
