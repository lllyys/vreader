// Purpose: feature #113 WI-2 (#110 Phase 3) — the remaining backup section DTOs beyond the
// WI-1 core: settings, book-sources, per-book-settings (+ PerBookSettingsOverride),
// replacement-rules, reading-history (schema v2), and ai-conversations (schema v3).
// Field-name-identical to the Swift reference (BackupSectionDTOs.swift +
// BackupReadingHistory.swift + BackupAIConversations.swift + PerBookSettings.swift). Swift
// `Data` fields use Base64DataSerializer; CGFloat maps to Double; nil optionals omitted.
package vreader.contracts.backup

import kotlinx.serialization.Serializable
import java.time.Instant

// MARK: - Settings (UserDefaults snapshot, type-tagged values)

@Serializable
data class BackupSettingsEnvelope(
    override val schemaVersion: Int,
    val defaults: Map<String, BackupDefaultsValue>,
) : BackupVersionedEnvelope

// MARK: - Book Sources (OPDS / source config; rule blobs are base64 Data)

@Serializable
data class BackupBookSourcesEnvelope(
    override val schemaVersion: Int,
    val sources: List<BackupBookSource>,
) : BackupVersionedEnvelope

@Serializable
data class BackupBookSource(
    val sourceURL: String,
    val sourceName: String,
    val sourceGroup: String? = null,
    val sourceType: Int,
    val enabled: Boolean,
    val searchURL: String? = null,
    val header: String? = null,
    @Serializable(Base64DataSerializer::class) val ruleSearchData: ByteArray? = null,
    @Serializable(Base64DataSerializer::class) val ruleBookInfoData: ByteArray? = null,
    @Serializable(Base64DataSerializer::class) val ruleTocData: ByteArray? = null,
    @Serializable(Base64DataSerializer::class) val ruleContentData: ByteArray? = null,
    val compatibilityLevel: String? = null,
    @Serializable(IsoInstantSerializer::class) val lastUpdateTime: Instant? = null,
    val customOrder: Int,
)

// MARK: - Per-Book Settings

@Serializable
data class BackupPerBookSettingsEnvelope(
    override val schemaVersion: Int,
    val entries: List<BackupPerBookSettingsEntry>,
) : BackupVersionedEnvelope

@Serializable
data class BackupPerBookSettingsEntry(
    val bookFingerprintKey: String,
    val override: PerBookSettingsOverride,
)

/** Per-book reader overrides — mirrors Swift `PerBookSettingsOverride` (CGFloat ⇒ Double).
 *  All fields optional; a nil inherits the global default. */
@Serializable
data class PerBookSettingsOverride(
    val fontSize: Double? = null,
    val fontName: String? = null,
    val lineSpacing: Double? = null,
    val letterSpacing: Double? = null,
    val themeName: String? = null,
    val bilingualEnabled: Boolean? = null,
    val bilingualTargetLanguage: String? = null,
    val bilingualGranularity: String? = null,
    val metricsReadout: String? = null,
)

// MARK: - Replacement Rules

@Serializable
data class BackupReplacementRulesEnvelope(
    override val schemaVersion: Int,
    val rules: List<BackupReplacementRule>,
) : BackupVersionedEnvelope

@Serializable
data class BackupReplacementRule(
    val ruleId: String,
    val pattern: String,
    val replacement: String,
    val isRegex: Boolean,
    val scopeKey: String,
    val enabled: Boolean,
    val order: Int,
    val label: String,
    @Serializable(IsoInstantSerializer::class) val createdAt: Instant,
)

// MARK: - Reading History (schema v2)

@Serializable
data class BackupReadingHistoryEnvelope(
    override val schemaVersion: Int,
    val sessions: List<BackupReadingSession>,
    val stats: List<BackupReadingStats>,
) : BackupVersionedEnvelope

@Serializable
data class BackupReadingSession(
    val sessionId: String,
    val bookFingerprintKey: String,
    @Serializable(IsoInstantSerializer::class) val startedAt: Instant,
    @Serializable(IsoInstantSerializer::class) val endedAt: Instant? = null,
    val durationSeconds: Int,
    val pagesRead: Int? = null,
    val wordsRead: Int? = null,
    val startLocatorJSON: String? = null,
    val endLocatorJSON: String? = null,
    val deviceId: String,
    val isRecovered: Boolean,
)

@Serializable
data class BackupReadingStats(
    val bookFingerprintKey: String,
    val totalReadingSeconds: Int,
    val sessionCount: Int,
    @Serializable(IsoInstantSerializer::class) val lastReadAt: Instant? = null,
    val averagePagesPerHour: Double? = null,
    val averageWordsPerMinute: Double? = null,
    val totalPagesRead: Int? = null,
    val totalWordsRead: Int? = null,
    val longestSessionSeconds: Int,
)

// MARK: - AI Conversations (schema v3)

@Serializable
data class BackupAIConversationsEnvelope(
    override val schemaVersion: Int,
    val sessions: List<BackupChatSession>,
) : BackupVersionedEnvelope

@Serializable
data class BackupChatSession(
    val sessionId: String,
    val bookFingerprintKey: String,
    val title: String,
    @Serializable(Base64DataSerializer::class) val messagesPayloadData: ByteArray? = null,
    val lastMessageSnippet: String,
    val messageCount: Int,
    @Serializable(IsoInstantSerializer::class) val createdAt: Instant,
    @Serializable(IsoInstantSerializer::class) val updatedAt: Instant,
)
