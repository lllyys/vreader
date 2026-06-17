package vreader.contracts

import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.security.MessageDigest

/**
 * Which reader engine produced the authoritative locator in a [VReaderLocator]
 * (mirrors Swift `ReaderLocatorEngine`). Exactly two persisted cases.
 */
enum class ReaderLocatorEngine {
    /** The legacy bespoke EPUB WKWebView engine — locator lives in `legacyLocator`. */
    epubWKWebView,

    /** The Readium toolkit engine — locator lives in `readiumLocatorJSON`. */
    readium,
}

/**
 * Durable, engine-agnostic reading-position envelope — the Kotlin mirror of Swift
 * `VReaderLocator` (vreader/Models/VReaderLocator.swift). The persistence layer
 * stores THIS, never a bare [Locator] (feature #106 Gate-2 Critical): saved
 * positions survive an engine swap / re-conversion because the envelope records
 * which engine is authoritative plus the canonical fallback.
 *
 * - `readiumLocatorJSON` — Readium's own CFI-bearing JSON (platform-local; the
 *   cross-platform fallback is `legacyLocator`'s progression + textQuote).
 * - `legacyLocator` — the engine-neutral [Locator] (canonical resume anchor).
 * - `schemaVersion` — the envelope's own migration hook, independent of the Room
 *   database schema version.
 *
 * `@Serializable` so the Room layer can JSON-encode the whole envelope into one
 * column (the iOS analog persists it as `Data?` on `ReadingPosition`).
 */
@Serializable
data class VReaderLocator(
    val fingerprintKey: String,
    val originalFormat: BookFormat,
    val engine: ReaderLocatorEngine,
    val readiumLocatorJSON: String? = null,
    val legacyLocator: Locator? = null,
    val schemaVersion: Int = CURRENT_SCHEMA_VERSION,
) {
    /**
     * SHA-256 (hex) of this envelope's deterministic JSON encoding — stable across
     * encode/decode round-trips, for local dedup/sync keys (mirrors Swift
     * `VReaderLocator.canonicalHash`).
     *
     * NOTE: this is **locally** deterministic (kotlinx fixed field order). It is
     * NOT yet asserted byte-equal to Swift's `JSONEncoder(.sortedKeys)` output —
     * cross-platform *envelope*-vector parity is the deferred WI-2 conformance
     * extension. Use it for on-device dedup, not (yet) for cross-device sync keys.
     */
    val canonicalHash: String
        get() {
            val bytes = CANONICAL_JSON.encodeToString(this).toByteArray(Charsets.UTF_8)
            return MessageDigest.getInstance("SHA-256").digest(bytes)
                .joinToString("") { "%02x".format(it) }
        }

    companion object {
        /** Current envelope schema version (independent of the Room DB version). */
        const val CURRENT_SCHEMA_VERSION = 1

        private val CANONICAL_JSON = Json { encodeDefaults = true }

        /**
         * Wraps an engine-neutral [Locator] as a legacy-engine envelope, deriving
         * `fingerprintKey`/`originalFormat` from the locator's identity triple —
         * mirrors Swift `init(legacyLocator:)`. The format string must be a valid
         * [BookFormat] raw value (it came from a `DocumentFingerprint`).
         */
        fun wrapLegacy(
            legacyLocator: Locator,
            schemaVersion: Int = CURRENT_SCHEMA_VERSION,
        ): VReaderLocator {
            val format = BookFormat.entries.firstOrNull { it.name == legacyLocator.format }
                ?: error("invalid BookFormat raw value: ${legacyLocator.format}")
            return VReaderLocator(
                fingerprintKey = legacyLocator.fingerprintKey,
                originalFormat = format,
                engine = ReaderLocatorEngine.epubWKWebView,
                readiumLocatorJSON = null,
                legacyLocator = legacyLocator,
                schemaVersion = schemaVersion,
            )
        }
    }
}
