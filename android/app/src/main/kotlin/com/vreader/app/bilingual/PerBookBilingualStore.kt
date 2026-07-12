// Purpose: feature #131 WI-5 — persists the PER-BOOK bilingual config (enabled /
// targetLanguage / granularity) in DataStore-Preferences, keyed by the book's
// fingerprint key so two books are isolated. Follows the ReaderSettingsStore /
// AiProviderStore JSON-in-Preferences convention (a per-book String key holds one
// JSON blob; enums stored by NAME for forward-compat). Device-local until the backup
// collect/restore wiring lands (§7) — the backup contract's PerBookSettingsOverride
// slice is exactly bilingualEnabled / bilingualTargetLanguage / bilingualGranularity
// and carries NO `bilingualStyle` (Style descoped, §3), so this store has NO `style`.
//
// GRANULARITY IS PINNED TO `paragraph` IN v1 (round-4 H3): a `sentence` write is
// normalized to `paragraph` on the way in, so the store can never persist `sentence`.
// The `TranslationGranularity` enum keeps both cases as reserved-foundational code; only
// the render/cache/store path is paragraph-only in v1.
//
// @coordinates-with: TranslationGranularity.kt, BilingualLanguages.kt,
//   com.vreader.app.reader.settings.ReaderSettingsStore (DataStore convention),
//   dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md (WI-5)
package com.vreader.app.bilingual

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * One book's bilingual config. NO `style` field (Style descoped, §3). [granularity] is
 * always [TranslationGranularity.paragraph] in v1 — the store normalizes any other value.
 */
data class PerBookBilingualConfig(
    val enabled: Boolean = false,
    val targetLanguage: String = DEFAULT_TARGET_LANGUAGE,
    val granularity: TranslationGranularity = TranslationGranularity.paragraph,
) {
    companion object {
        /** The default target — Chinese, matching BILINGUAL_LANGS[0]. */
        val DEFAULT_TARGET_LANGUAGE: String get() = BilingualLanguages.ALL.first().key
    }
}

/** The persisted shape — enums as String names for forward-compat. */
@Serializable
private data class PerBookBilingualState(
    val enabled: Boolean = false,
    val targetLanguage: String = "Chinese",
    val granularity: String = "paragraph",
)

class PerBookBilingualStore(
    private val dataStore: DataStore<Preferences>,
    private val json: Json = Json { ignoreUnknownKeys = true; encodeDefaults = true },
) {

    /** A one-shot read of [bookKey]'s config (defaults when unset). */
    suspend fun read(bookKey: String): PerBookBilingualConfig =
        readState(dataStore.data.first(), bookKey).toConfig()

    /** A reactive stream of [bookKey]'s config — a host collects this and applies live. */
    fun observe(bookKey: String): Flow<PerBookBilingualConfig> =
        dataStore.data.map { readState(it, bookKey).toConfig() }

    /**
     * Persist [config] for [bookKey]. [config.granularity] is normalized to `paragraph`
     * in v1 (round-4 H3) — a `sentence` request is silently pinned to paragraph so the
     * store never persists `sentence`.
     */
    suspend fun write(bookKey: String, config: PerBookBilingualConfig) {
        dataStore.edit { prefs ->
            prefs[keyFor(bookKey)] = json.encodeToString(
                PerBookBilingualState(
                    enabled = config.enabled,
                    targetLanguage = config.targetLanguage,
                    granularity = TranslationGranularity.paragraph.name,  // pinned in v1
                ),
            )
        }
    }

    private fun readState(prefs: Preferences, bookKey: String): PerBookBilingualState {
        val raw = prefs[keyFor(bookKey)] ?: return PerBookBilingualState()
        return runCatching { json.decodeFromString<PerBookBilingualState>(raw) }.getOrDefault(PerBookBilingualState())
    }

    /** Map the persisted state → the value type; unknown language keeps as-is (findOrDefault
     *  is a display concern), unknown/`sentence` granularity clamps to paragraph (v1 pin). */
    private fun PerBookBilingualState.toConfig() = PerBookBilingualConfig(
        enabled = enabled,
        targetLanguage = targetLanguage,
        granularity = TranslationGranularity.paragraph,  // v1: paragraph only, always
    )

    private fun keyFor(bookKey: String) = stringPreferencesKey("$KEY_PREFIX$bookKey")

    companion object {
        private const val KEY_PREFIX = "bilingual_per_book_json:"
    }
}
