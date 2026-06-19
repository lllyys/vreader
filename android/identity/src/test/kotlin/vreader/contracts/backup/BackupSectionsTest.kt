package vreader.contracts.backup

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Feature #113 WI-1 — Kotlin backup-section DTOs + the Swift-parity JSON surface
 * (schema constants, ISO8601 dates, base64 Data, omitted nil optionals, sorted-key
 * canonical encode, core-section round-trips). The cross-platform golden-vector
 * conformance is WI-2.
 */
class BackupSectionsTest {

    // --- Schema constants (the contract) ---

    @Test fun schemaConstants_matchContract() {
        assertEquals(3, BackupSchema.CURRENT_SCHEMA_VERSION)
        assertEquals(setOf(1, 2, 3), BackupSchema.ACCEPTED_SCHEMA_VERSIONS)
        assertEquals(1, BackupSchema.MANIFEST_SCHEMA_VERSION)
    }

    @Test fun restoreError_equality() {
        assertEquals(
            BackupRestoreError.UnsupportedSchemaVersion("positions", 4, 3),
            BackupRestoreError.UnsupportedSchemaVersion("positions", 4, 3),
        )
        assertEquals(
            BackupRestoreError.PartialFailure("annotations", 2, 10),
            BackupRestoreError.PartialFailure("annotations", 2, 10),
        )
        assertFalse(
            BackupRestoreError.PartialFailure("a", 1, 2) ==
                BackupRestoreError.PartialFailure("a", 1, 3),
        )
    }

    // --- ISO8601 instant serializer (Swift .iso8601 parity) ---

    @Test fun isoInstant_emitsExactSecondPrecisionUtc() {
        val instant = Instant.parse("2026-06-20T16:30:00Z")
        val json = BackupJson.DEFAULT.encodeToString(IsoInstantSerializer, instant)
        assertEquals("\"2026-06-20T16:30:00Z\"", json)
        assertFalse(json.contains("."), "no fractional seconds")
    }

    @Test fun isoInstant_truncatesFractionalSeconds() {
        val instant = Instant.parse("2026-06-20T16:30:00.123456Z")
        val json = BackupJson.DEFAULT.encodeToString(IsoInstantSerializer, instant)
        assertEquals("\"2026-06-20T16:30:00Z\"", json)
    }

    @Test fun isoInstant_roundTrips() {
        val instant = Instant.parse("2026-06-20T16:30:00Z")
        val json = BackupJson.DEFAULT.encodeToString(IsoInstantSerializer, instant)
        val back = BackupJson.DEFAULT.decodeFromString(IsoInstantSerializer, json)
        assertEquals(instant, back)
    }

    @Test fun isoInstant_acceptsFractionalInputLeniently() {
        // An iOS-written value should always restore; truncation happens on re-emit.
        val parsed = BackupJson.DEFAULT.decodeFromString(IsoInstantSerializer, "\"2026-06-20T16:30:00.500Z\"")
        assertEquals(Instant.parse("2026-06-20T16:30:00.500Z"), parsed)
    }

    @Test fun isoInstant_pre1970AndFarFuture() {
        for (s in listOf("1969-12-31T23:59:59Z", "2999-01-01T00:00:00Z")) {
            val instant = Instant.parse(s)
            assertEquals("\"$s\"", BackupJson.DEFAULT.encodeToString(IsoInstantSerializer, instant))
        }
    }

    // --- Base64 Data serializer (Swift Data parity) ---

    @Test fun base64Data_encodesAsBase64String_andRoundTrips() {
        val bytes = byteArrayOf(1, 2, 3, 4)
        val json = BackupJson.DEFAULT.encodeToString(Base64DataSerializer, bytes)
        assertEquals("\"AQIDBA==\"", json)
        val back = BackupJson.DEFAULT.decodeFromString(Base64DataSerializer, json)
        assertTrue(bytes.contentEquals(back))
    }

    // --- Canonical sorted-key encode ---

    @Test fun canonicalElement_sortsObjectKeysRecursively() {
        val unsorted = JsonObject(
            mapOf(
                "b" to JsonPrimitive(1),
                "a" to JsonObject(mapOf("z" to JsonPrimitive(2), "y" to JsonPrimitive(3))),
            ),
        )
        val canon = BackupJson.canonicalElement(unsorted)
        val text = Json.encodeToString(JsonElement.serializer(), canon)
        assertTrue(text.indexOf("\"a\"") < text.indexOf("\"b\""), "top keys sorted a before b")
        assertTrue(text.indexOf("\"y\"") < text.indexOf("\"z\""), "nested keys sorted y before z")
    }

    // --- Omitted nil optionals (explicitNulls=false, Swift parity) ---

    @Test fun nilOptional_isOmittedFromJson() {
        val highlight = BackupHighlight(
            highlightId = "ID-1", bookFingerprintKey = "epub:abc:100", locatorJSON = "{}",
            selectedText = "hello", color = "yellow", note = null,
            createdAt = Instant.parse("2026-01-01T00:00:00Z"),
            updatedAt = Instant.parse("2026-01-01T00:00:00Z"),
        )
        val json = BackupJson.encode(highlight)
        assertFalse(json.contains("\"note\""), "null note omitted")
        // A present optional IS encoded.
        val json2 = BackupJson.encode(highlight.copy(note = "a note"))
        assertTrue(json2.contains("\"note\""))
    }

    @Test fun libraryEntry_nullSourceCanonicalKeyOmitted_presentRoundTrips() {
        val entry = BackupLibraryEntry(
            fingerprintKey = "azw3:src:200", format = "azw3", sha256 = "src", byteCount = 200,
            originalExtension = "mobi", title = "标题", author = null,
            addedAt = Instant.parse("2026-01-01T00:00:00Z"), lastOpenedAt = null,
            blobPath = "VReader/books/azw3/src_200.azw3", sourceCanonicalKey = null,
        )
        val json = BackupJson.encode(entry)
        assertFalse(json.contains("\"sourceCanonicalKey\""), "null sourceCanonicalKey omitted")
        assertFalse(json.contains("\"author\""), "null author omitted")
        assertEquals(entry, BackupJson.decode<BackupLibraryEntry>(json))

        val keyed = entry.copy(sourceCanonicalKey = "azw3:src:200")
        val json2 = BackupJson.encode(keyed)
        assertTrue(json2.contains("\"sourceCanonicalKey\""))
        assertEquals(keyed, BackupJson.decode<BackupLibraryEntry>(json2))
    }

    // --- Core section round-trips + field names ---

    @Test fun annotationsEnvelope_roundTrips_withFieldNames() {
        val env = BackupAnnotationsEnvelope(
            schemaVersion = 3,
            highlights = listOf(
                BackupHighlight(
                    "H1", "epub:abc:100", "{\"x\":1}", "selected", "yellow", "note text",
                    Instant.parse("2026-01-01T00:00:00Z"), Instant.parse("2026-01-02T00:00:00Z"),
                ),
            ),
            bookmarks = listOf(
                BackupBookmark(
                    "B1", "epub:abc:100", "{}", "Chapter 1",
                    Instant.parse("2026-01-01T00:00:00Z"), Instant.parse("2026-01-01T00:00:00Z"),
                ),
            ),
            notes = listOf(
                BackupNote(
                    "N1", "epub:abc:100", "{}", "my note 中文",
                    Instant.parse("2026-01-01T00:00:00Z"), Instant.parse("2026-01-01T00:00:00Z"),
                ),
            ),
        )
        val json = BackupJson.encode(env)
        for (field in listOf("schemaVersion", "bookFingerprintKey", "locatorJSON", "highlightId", "selectedText")) {
            assertTrue(json.contains("\"$field\""), "field $field present")
        }
        assertEquals(env, BackupJson.decode<BackupAnnotationsEnvelope>(json))
    }

    @Test fun positionsEnvelope_roundTrips_withNullLastOpened() {
        val env = BackupPositionsEnvelope(
            schemaVersion = 3,
            positions = listOf(
                BackupPosition("epub:abc:100", "{\"progression\":0.5}", Instant.parse("2026-01-01T00:00:00Z"), null),
                BackupPosition("txt:def:200", "{}", Instant.parse("2026-01-01T00:00:00Z"), Instant.parse("2026-01-03T00:00:00Z")),
            ),
        )
        val json = BackupJson.encode(env)
        assertTrue(json.contains("\"locatorJSON\""))
        assertEquals(env, BackupJson.decode<BackupPositionsEnvelope>(json))
    }

    @Test fun collectionsEnvelope_roundTrips_empty_andPopulated() {
        val empty = BackupCollectionsEnvelope(3, emptyList())
        assertEquals(empty, BackupJson.decode<BackupCollectionsEnvelope>(BackupJson.encode(empty)))

        val env = BackupCollectionsEnvelope(
            3, listOf(BackupCollection("收藏", Instant.parse("2026-01-01T00:00:00Z"), listOf("epub:abc:100", "txt:def:200"))),
        )
        assertEquals(env, BackupJson.decode<BackupCollectionsEnvelope>(BackupJson.encode(env)))
    }

    @Test fun libraryManifestEnvelope_roundTrips() {
        val env = BackupLibraryManifestEnvelope(
            schemaVersion = 1,
            books = listOf(
                BackupLibraryEntry(
                    "epub:abc:100", "epub", "abc", 100, "epub", "Title", "Author",
                    Instant.parse("2026-01-01T00:00:00Z"), Instant.parse("2026-01-05T00:00:00Z"),
                    "VReader/books/epub/abc_100.epub", null,
                ),
            ),
        )
        val json = BackupJson.encode(env)
        assertTrue(json.contains("\"blobPath\""))
        assertTrue(json.contains("\"fingerprintKey\""))
        assertEquals(env, BackupJson.decode<BackupLibraryManifestEnvelope>(json))
    }

    @Test fun metadata_roundTrips() {
        val meta = BackupMetadata(
            id = "UUID-1", createdAt = Instant.parse("2026-06-20T16:30:00Z"),
            deviceName = "Pixel 7", appVersion = "0.6.0", bookCount = 12, totalSizeBytes = 123456789L,
        )
        val json = BackupJson.encode(meta)
        assertTrue(json.contains("\"2026-06-20T16:30:00Z\""))
        assertEquals(meta, BackupJson.decode<BackupMetadata>(json))
    }

    @Test fun position_dateSerializesAsIso8601InSection() {
        val env = BackupPositionsEnvelope(3, listOf(BackupPosition("k", "{}", Instant.parse("2026-06-20T16:30:00Z"), null)))
        assertTrue(BackupJson.encode(env).contains("\"2026-06-20T16:30:00Z\""))
    }
}
