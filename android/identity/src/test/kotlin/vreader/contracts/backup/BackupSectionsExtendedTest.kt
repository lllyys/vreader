package vreader.contracts.backup

import java.time.Instant
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Feature #113 WI-2 — the remaining backup section DTOs (settings/book-sources/
 * per-book-settings/replacement-rules/reading-history/ai-conversations) + the type-tagged
 * `BackupDefaultsValue` union. ByteArray-bearing DTOs (book-source rule blobs, chat payload)
 * are round-tripped via re-encode equality since data-class equals can't compare arrays.
 */
class BackupSectionsExtendedTest {

    /** encode → decode → re-encode; assert the two JSONs match (round-trip for ByteArray DTOs). */
    private inline fun <reified T> assertJsonRoundTrips(value: T) {
        val json1 = BackupJson.encode(value)
        val decoded = BackupJson.decode<T>(json1)
        val json2 = BackupJson.encode(decoded)
        assertEquals(json1, json2)
    }

    // --- BackupDefaultsValue type-tagged union ---

    @Test fun defaultsValue_eachTaggedCase_shapeAndRoundTrip() {
        val cases = mapOf(
            BackupDefaultsValue.Bool(true) to "bool",
            BackupDefaultsValue.IntValue(42L) to "int",
            BackupDefaultsValue.DoubleValue(3.5) to "double",
            BackupDefaultsValue.Str("hi") to "string",
            BackupDefaultsValue.DataValue(byteArrayOf(1, 2, 3)) to "data",
        )
        for ((value, tag) in cases) {
            val json = BackupJson.encode(value)
            assertTrue(json.contains("\"type\""), "type key present for $tag")
            assertTrue(json.contains("\"$tag\""), "tag $tag present")
            assertTrue(json.contains("\"value\""), "value key present for $tag")
            assertEquals(value, BackupJson.decode<BackupDefaultsValue>(json))
        }
    }

    @Test fun defaultsValue_int_is64Bit() {
        // Swift Int is Int64 on iOS — a value beyond 32-bit must round-trip (Gate-4 Medium).
        val big = BackupDefaultsValue.IntValue(Int.MAX_VALUE.toLong() + 1L)
        assertEquals(big, BackupJson.decode<BackupDefaultsValue>(BackupJson.encode<BackupDefaultsValue>(big)))
    }

    @Test fun defaultsValue_data_isBase64() {
        val json = BackupJson.encode<BackupDefaultsValue>(BackupDefaultsValue.DataValue(byteArrayOf(1, 2, 3, 4)))
        assertTrue(json.contains("AQIDBA=="), "data value is base64")
    }

    @Test fun settingsEnvelope_roundTrips() {
        val env = BackupSettingsEnvelope(
            schemaVersion = 3,
            defaults = mapOf(
                "readerTheme" to BackupDefaultsValue.Str("dark"),
                "readerAutoPageTurn" to BackupDefaultsValue.Bool(true),
                "readerAutoPageTurnInterval" to BackupDefaultsValue.DoubleValue(3.0),
            ),
        )
        assertEquals(env, BackupJson.decode<BackupSettingsEnvelope>(BackupJson.encode(env)))
    }

    // --- Book sources (ByteArray rule blobs) ---

    @Test fun bookSource_withRuleData_roundTrips_andNullDataOmitted() {
        val withData = BackupBookSource(
            sourceURL = "https://opds.example/catalog", sourceName = "Example", sourceType = 1,
            enabled = true, ruleSearchData = byteArrayOf(9, 8, 7), customOrder = 0,
            lastUpdateTime = Instant.parse("2026-06-20T16:30:00Z"),
        )
        val json = BackupJson.encode(BackupBookSourcesEnvelope(3, listOf(withData)))
        assertTrue(json.contains("\"ruleSearchData\""), "present rule data encoded")
        assertFalse(json.contains("\"ruleTocData\""), "null rule data omitted")
        assertJsonRoundTrips(BackupBookSourcesEnvelope(3, listOf(withData)))
    }

    // --- Per-book settings + override ---

    @Test fun perBookOverride_roundTrips_andNullsOmitted() {
        val entry = BackupPerBookSettingsEntry(
            bookFingerprintKey = "epub:abc:100",
            override = PerBookSettingsOverride(fontSize = 18.0, bilingualEnabled = true, bilingualTargetLanguage = "Chinese"),
        )
        val env = BackupPerBookSettingsEnvelope(3, listOf(entry))
        val json = BackupJson.encode(env)
        assertTrue(json.contains("\"fontSize\""))
        assertTrue(json.contains("\"bilingualEnabled\""))
        assertFalse(json.contains("\"fontName\""), "null override field omitted")
        assertEquals(env, BackupJson.decode<BackupPerBookSettingsEnvelope>(json))
    }

    @Test fun perBookOverride_emptyOverride_roundTrips() {
        val env = BackupPerBookSettingsEnvelope(3, listOf(BackupPerBookSettingsEntry("k", PerBookSettingsOverride())))
        assertEquals(env, BackupJson.decode<BackupPerBookSettingsEnvelope>(BackupJson.encode(env)))
    }

    // --- Replacement rules ---

    @Test fun replacementRules_roundTrip() {
        val env = BackupReplacementRulesEnvelope(
            3,
            listOf(
                BackupReplacementRule(
                    ruleId = "R1", pattern = "foo", replacement = "bar", isRegex = false,
                    scopeKey = "global", enabled = true, order = 0, label = "rule 中文",
                    createdAt = Instant.parse("2026-06-20T16:30:00Z"),
                ),
            ),
        )
        assertEquals(env, BackupJson.decode<BackupReplacementRulesEnvelope>(BackupJson.encode(env)))
    }

    // --- Reading history (schema v2) ---

    @Test fun readingHistory_roundTrips_withNullableFields() {
        val env = BackupReadingHistoryEnvelope(
            schemaVersion = 3,
            sessions = listOf(
                BackupReadingSession(
                    sessionId = "S1", bookFingerprintKey = "epub:abc:100",
                    startedAt = Instant.parse("2026-06-20T16:00:00Z"), endedAt = Instant.parse("2026-06-20T16:30:00Z"),
                    durationSeconds = 1800, pagesRead = 12, wordsRead = null,
                    startLocatorJSON = "{}", endLocatorJSON = null, deviceId = "dev-1", isRecovered = false,
                ),
            ),
            stats = listOf(
                BackupReadingStats(
                    bookFingerprintKey = "epub:abc:100", totalReadingSeconds = 3600, sessionCount = 2,
                    lastReadAt = Instant.parse("2026-06-20T16:30:00Z"), averagePagesPerHour = 24.0,
                    averageWordsPerMinute = null, totalPagesRead = 24, totalWordsRead = null, longestSessionSeconds = 1800,
                ),
            ),
        )
        val json = BackupJson.encode(env)
        assertFalse(json.contains("\"wordsRead\""), "null session field omitted")
        assertEquals(env, BackupJson.decode<BackupReadingHistoryEnvelope>(json))
    }

    // --- AI conversations (schema v3, ByteArray payload) ---

    @Test fun aiConversations_roundTrips_andNullPayloadOmitted() {
        val withPayload = BackupChatSession(
            sessionId = "C1", bookFingerprintKey = "epub:abc:100", title = "Chat",
            messagesPayloadData = byteArrayOf(5, 6, 7), lastMessageSnippet = "hi 中文", messageCount = 3,
            createdAt = Instant.parse("2026-06-20T16:00:00Z"), updatedAt = Instant.parse("2026-06-20T16:30:00Z"),
        )
        val json = BackupJson.encode(BackupAIConversationsEnvelope(3, listOf(withPayload)))
        assertTrue(json.contains("\"messagesPayloadData\""), "present payload encoded as base64")
        assertJsonRoundTrips(BackupAIConversationsEnvelope(3, listOf(withPayload)))

        val noPayload = withPayload.copy(messagesPayloadData = null)
        val json2 = BackupJson.encode(BackupAIConversationsEnvelope(3, listOf(noPayload)))
        assertFalse(json2.contains("\"messagesPayloadData\""), "null payload omitted")
    }
}
