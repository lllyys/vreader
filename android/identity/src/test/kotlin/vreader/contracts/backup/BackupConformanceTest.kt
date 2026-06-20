package vreader.contracts.backup

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.int
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * Feature #113 WI-3 — the cross-platform backup-format conformance (Kotlin side). Decodes every
 * section in the SHARED golden vector `contracts/vectors/backup-sections.json` into its Kotlin
 * DTO, re-encodes, and asserts the re-encode's PARSED JSON equals the vector's — semantic
 * equality (key order / whitespace insignificant). The Swift conformance
 * (vreaderTests/Contracts/BackupConformanceTests.swift) asserts the SAME vector with the iOS
 * DTOs; both green ⇒ a backup written by one platform restores on the other.
 */
class BackupConformanceTest {
    private val vectorsDir = File(
        System.getProperty("vreader.vectors.dir")
            ?: error("vreader.vectors.dir not set — run via the :identity:test task (it injects it)"),
    )

    private val root: JsonObject by lazy {
        Json.parseToJsonElement(File(vectorsDir, "backup-sections.json").readText()).jsonObject
    }
    private val sections: JsonObject by lazy { root.getValue("sections").jsonObject }

    /** Decode the section JSON into [T], re-encode, and assert semantic round-trip parity. */
    private inline fun <reified T> assertRoundTrips(name: String) {
        val vector = sections.getValue(name)
        val dto = BackupJson.DEFAULT.decodeFromJsonElement<T>(vector)
        val reEncoded: JsonElement = BackupJson.DEFAULT.encodeToJsonElement(dto)
        assertEquals(
            BackupJson.canonicalElement(vector),
            BackupJson.canonicalElement(reEncoded),
            "section '$name' did not round-trip to the golden vector",
        )
    }

    @Test fun schemaConstants_matchVector() {
        assertEquals(root.getValue("schemaVersion").jsonPrimitive.int, BackupSchema.CURRENT_SCHEMA_VERSION)
        assertEquals(root.getValue("manifestSchemaVersion").jsonPrimitive.int, BackupSchema.MANIFEST_SCHEMA_VERSION)
        assertTrue(BackupSchema.CURRENT_SCHEMA_VERSION in BackupSchema.ACCEPTED_SCHEMA_VERSIONS)
    }

    @Test fun annotations_roundTrips() = assertRoundTrips<BackupAnnotationsEnvelope>("annotations")
    @Test fun positions_roundTrips() = assertRoundTrips<BackupPositionsEnvelope>("positions")
    @Test fun collections_roundTrips() = assertRoundTrips<BackupCollectionsEnvelope>("collections")
    @Test fun libraryManifest_roundTrips() = assertRoundTrips<BackupLibraryManifestEnvelope>("library-manifest")
    @Test fun settings_roundTrips() = assertRoundTrips<BackupSettingsEnvelope>("settings")
    @Test fun bookSources_roundTrips() = assertRoundTrips<BackupBookSourcesEnvelope>("book-sources")
    @Test fun perBookSettings_roundTrips() = assertRoundTrips<BackupPerBookSettingsEnvelope>("per-book-settings")
    @Test fun replacementRules_roundTrips() = assertRoundTrips<BackupReplacementRulesEnvelope>("replacement-rules")
    @Test fun readingHistory_roundTrips() = assertRoundTrips<BackupReadingHistoryEnvelope>("reading-history")
    @Test fun aiConversations_roundTrips() = assertRoundTrips<BackupAIConversationsEnvelope>("ai-conversations")
    @Test fun metadata_roundTrips() = assertRoundTrips<BackupMetadata>("metadata")
}
