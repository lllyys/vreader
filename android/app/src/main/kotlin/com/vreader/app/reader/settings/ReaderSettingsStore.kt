// Purpose: feature #129 WI-1 (#110 Phase 3) — persists the reader "Display" [ReaderSettings] in
// DataStore (the OpdsSourceStore / AiProviderStore JSON-in-Preferences precedent). Global, device-
// local (NOT backed up — display prefs are per-device, like iOS UserDefaults). Exposes a reactive
// [settings] Flow the reader hosts collect, and clamped suspend setters. Enum fields are stored by
// NAME so an unknown/old value decodes to the default (forward-compatible).
package com.vreader.app.reader.settings

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** The persisted shape — enums as String names for forward-compat; clamped on read AND write. */
@Serializable
private data class ReaderSettingsState(
    val theme: String = ReaderTheme.Paper.name,
    val fontFamily: String = ReaderFontFamily.Serif.name,
    val fontSizeSp: Float = ReaderSettings.DEFAULT_FONT_SIZE,
    val lineSpacing: Float = ReaderSettings.DEFAULT_LINE_SPACING,
    val marginDp: Float = ReaderSettings.DEFAULT_MARGIN,
)

class ReaderSettingsStore(
    private val dataStore: DataStore<Preferences>,
    private val json: Json = Json { ignoreUnknownKeys = true; encodeDefaults = true },
) {
    // feature #129 WI-4 — one process-wide serializer for the read-modify-write setters. The store is
    // a container singleton, so this Mutex orders EVERY setter across ALL callers (a reader Activity,
    // its rotation replacement, a second reader) — a slider burst dispatched from independent appScope
    // coroutines can otherwise reach DataStore's internal actor out of submission order and restore a
    // stale value. `withLock` is exception-safe: a throwing/cancelled setter releases the lock and can
    // never wedge the queue (the hazard a hand-rolled channel+consumer had). Gate-4 High (WI-4 audit).
    private val writeMutex = Mutex()
    /** The reactive settings stream — a host collects this (`collectAsStateWithLifecycle`) and applies
     *  live; emits the defaults until the user changes something. */
    val settings: Flow<ReaderSettings> = dataStore.data.map { read(it).toSettings() }

    /** A one-shot read (the current settings) — for a host's initial config at open. */
    suspend fun current(): ReaderSettings = read(dataStore.data.first()).toSettings()

    suspend fun setTheme(theme: ReaderTheme) = update { it.copy(theme = theme.name) }
    suspend fun setFontFamily(family: ReaderFontFamily) = update { it.copy(fontFamily = family.name) }
    suspend fun setFontSize(sp: Float) = update { it.copy(fontSizeSp = ReaderSettings.clampFontSize(sp)) }
    suspend fun setLineSpacing(v: Float) = update { it.copy(lineSpacing = ReaderSettings.clampLineSpacing(v)) }
    suspend fun setMargin(dp: Float) = update { it.copy(marginDp = ReaderSettings.clampMargin(dp)) }

    private suspend fun update(transform: (ReaderSettingsState) -> ReaderSettingsState) = writeMutex.withLock {
        // Normalize EVERY numeric field on write (not just the one being set) so a previously
        // hand-edited / older out-of-range value is healed on the next write — truly "clamped on write".
        // The Mutex serializes concurrent setters so submission order == commit order (Gate-4 High).
        dataStore.edit { prefs -> prefs[KEY] = json.encodeToString(transform(read(prefs)).normalized()) }
    }

    private fun ReaderSettingsState.normalized() = copy(
        fontSizeSp = ReaderSettings.clampFontSize(fontSizeSp),
        lineSpacing = ReaderSettings.clampLineSpacing(lineSpacing),
        marginDp = ReaderSettings.clampMargin(marginDp),
    )

    private fun read(prefs: Preferences): ReaderSettingsState {
        val raw = prefs[KEY] ?: return ReaderSettingsState()
        return runCatching { json.decodeFromString<ReaderSettingsState>(raw) }.getOrDefault(ReaderSettingsState())
    }

    /** Map the persisted state → the value type, defaulting unknown enum names and clamping ranges
     *  (so a hand-edited / older file can never yield an out-of-range or unreadable setting). */
    private fun ReaderSettingsState.toSettings() = ReaderSettings(
        theme = runCatching { ReaderTheme.valueOf(theme) }.getOrDefault(ReaderTheme.Paper),
        fontFamily = runCatching { ReaderFontFamily.valueOf(fontFamily) }.getOrDefault(ReaderFontFamily.Serif),
        fontSizeSp = ReaderSettings.clampFontSize(fontSizeSp),
        lineSpacing = ReaderSettings.clampLineSpacing(lineSpacing),
        marginDp = ReaderSettings.clampMargin(marginDp),
    )

    companion object {
        private val KEY = stringPreferencesKey("reader_settings_json")
    }
}
