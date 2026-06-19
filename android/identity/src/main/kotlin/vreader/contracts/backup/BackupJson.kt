// Purpose: feature #113 WI-1 (#110 Phase 3) — the canonical encode/decode surface for
// backup section DTOs, configured for SWIFT Codable PARITY (Gate-2 round-1 Highs):
//   - explicitNulls = false      → nil optionals are OMITTED (Swift drops nil keys)
//   - IsoInstantSerializer       → Date ⇒ ISO8601 UTC, second precision (Swift .iso8601)
//   - Base64DataSerializer       → Data ⇒ base64 String (Swift Data JSON encoding)
//   - canonicalElement()         → recursive object-key sort (Swift .sortedKeys), used by
//                                  the WI-2 conformance which compares PARSED JsonElement
//                                  equality (robust to .prettyPrinted whitespace).
// Pure JVM; mirrors the existing VReaderLocator.CANONICAL_JSON precedent.
package vreader.contracts.backup

import kotlinx.serialization.KSerializer
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import java.time.Instant
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit
import java.util.Base64

/** ISO8601 UTC, second precision, no fractional seconds — emits exactly
 *  `2026-06-20T16:30:00Z`, matching Swift `JSONEncoder.dateEncodingStrategy = .iso8601`
 *  (= `ISO8601DateFormatter` default). Decode is lenient (accepts fractional/offset forms
 *  via `Instant.parse`) so an iOS-written value always restores. */
object IsoInstantSerializer : KSerializer<Instant> {
    private val FORMAT: DateTimeFormatter =
        DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss'Z'").withZone(ZoneOffset.UTC)

    override val descriptor =
        PrimitiveSerialDescriptor("vreader.backup.IsoInstant", PrimitiveKind.STRING)

    override fun serialize(encoder: Encoder, value: Instant) {
        encoder.encodeString(FORMAT.format(value.truncatedTo(ChronoUnit.SECONDS)))
    }

    override fun deserialize(decoder: Decoder): Instant = Instant.parse(decoder.decodeString())
}

/** Swift `Data` ⇒ base64 String (matches `JSONEncoder` default for `Data`). */
object Base64DataSerializer : KSerializer<ByteArray> {
    override val descriptor =
        PrimitiveSerialDescriptor("vreader.backup.Base64Data", PrimitiveKind.STRING)

    override fun serialize(encoder: Encoder, value: ByteArray) {
        encoder.encodeString(Base64.getEncoder().encodeToString(value))
    }

    override fun deserialize(decoder: Decoder): ByteArray =
        Base64.getDecoder().decode(decoder.decodeString())
}

/** Canonical encode/decode surface for backup section DTOs. */
object BackupJson {
    /** explicitNulls=false (omit nil optionals, Swift parity); encodeDefaults=true (round-trip
     *  optional-with-default like `sourceCanonicalKey`); ignoreUnknownKeys (tolerate a newer
     *  archive's extra keys on decode). */
    val DEFAULT: Json = Json {
        encodeDefaults = true
        explicitNulls = false
        ignoreUnknownKeys = true
    }

    inline fun <reified T> encode(value: T): String = DEFAULT.encodeToString(value)

    inline fun <reified T> decode(json: String): T = DEFAULT.decodeFromString(json)

    /** Recursively sort object keys (Swift `.sortedKeys`). The conformance compares the
     *  parsed-and-sorted element of an iOS vector vs the Kotlin re-encode — semantic
     *  equality, robust to `.prettyPrinted` whitespace. */
    fun canonicalElement(element: JsonElement): JsonElement = when (element) {
        is JsonObject -> JsonObject(element.toSortedMap().mapValues { canonicalElement(it.value) })
        is JsonArray -> JsonArray(element.map { canonicalElement(it) })
        else -> element
    }
}
