// Purpose: feature #129 WI-1 (#110 Phase 3) — persists the reader "Display" [ReaderSettings] in
// DataStore (the OpdsSourceStore / AiProviderStore JSON-in-Preferences precedent). Global, device-
// local (NOT backed up — display prefs are per-device, like iOS UserDefaults). Exposes a reactive
// [settings] Flow the reader hosts collect, and clamped suspend setters. Enum fields are stored by
// NAME so an unknown/old value decodes to the default (forward-compatible).
package com.vreader.app.reader.settings

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.util.concurrent.atomic.AtomicLong

/** The persisted shape — enums as String names for forward-compat; clamped on read AND write. */
@Serializable
private data class ReaderSettingsState(
    val theme: String = ReaderTheme.Paper.name,
    val fontFamily: String = ReaderFontFamily.Serif.name,
    val fontSizeSp: Float = ReaderSettings.DEFAULT_FONT_SIZE,
    val lineSpacing: Float = ReaderSettings.DEFAULT_LINE_SPACING,
    val marginDp: Float = ReaderSettings.DEFAULT_MARGIN,
    val layout: String = ReaderLayout.Scroll.name,
)

class ReaderSettingsStore(
    private val dataStore: DataStore<Preferences>,
    private val json: Json = Json { ignoreUnknownKeys = true; encodeDefaults = true },
) {
    // feature #129 WI-4 (Gate-4 High) — the store is the single process-wide write serializer (it is a
    // container singleton, so it orders EVERY setter across ALL callers: a reader, its rotation
    // replacement, a second reader). Two mechanisms combine, because a bare Mutex gives mutual exclusion
    // but NOT FIFO acquisition — an older slider value could otherwise win the lock last and commit stale:
    //   1. `writeMutex` makes each read-modify-write atomic (no interleaved edit clobbers another field);
    //   2. a monotonic submission sequence keyed per FIELD: inside the lock a same-field write is DROPPED
    //      if a newer sequence already committed — so latest-submission-wins holds regardless of
    //      lock-acquisition order.
    // The sequence MUST be stamped at the caller's true submission point, not at the coroutine's entry:
    // the reader fires each slider edit as a fire-and-forget `launch` on a multi-threaded dispatcher, so
    // stamping inside the setter body would inherit the dispatcher's (unordered) start order. `nextSeq()`
    // is therefore called SYNCHRONOUSLY on the main thread in the UI callback, in slider order, and the
    // sequence is passed into the suspend setter. `withLock` is exception-safe: a throwing/cancelled
    // setter releases the lock and can never wedge the queue.
    private val writeMutex = Mutex()
    private val seq = AtomicLong(0)
    private val committedSeqByField = HashMap<Field, Long>()

    private enum class Field { THEME, FONT_FAMILY, FONT_SIZE, LINE_SPACING, MARGIN, LAYOUT }

    /** Allocate the next monotonic submission sequence. Call this SYNCHRONOUSLY at the UI callback (on
     *  the main thread, in edit order) and pass the result into the setter, so latest-wins reflects the
     *  user's actual edit order — not the dispatcher's coroutine-start order. */
    fun nextSeq(): Long = seq.incrementAndGet()

    /** The reactive settings stream — a host collects this (`collectAsStateWithLifecycle`) and applies
     *  live; emits the defaults until the user changes something. */
    val settings: Flow<ReaderSettings> = dataStore.data.map { read(it).toSettings() }

    /** A one-shot read (the current settings) — for a host's initial config at open. */
    suspend fun current(): ReaderSettings = read(dataStore.data.first()).toSettings()

    // feature #137 WI-6b — the first-open paged tap-zone hint's one-shot discoverability flag
    // (vreader-reader.jsx:29 `localStorage.getItem('vreader.tap-hint-seen')` analog). Persisted under
    // its OWN preference key, NOT inside the display-settings JSON — so this device-local flag is
    // independent of the live-collected typography flow (reading/writing it never re-renders the reader
    // body). Default false → the hint shows once per install until dismissed.

    /** True once the first-open paged tap-zone hint has been shown + dismissed (persisted). */
    suspend fun tapHintSeen(): Boolean = dataStore.data.first()[TAP_HINT_SEEN_KEY] ?: false

    /** Mark the paged tap-zone hint as seen so it never shows again (idempotent). */
    suspend fun markTapHintSeen() { dataStore.edit { it[TAP_HINT_SEEN_KEY] = true } }

    /** Reset the seen flag (test-only — restores the first-open hint eligibility). */
    @androidx.annotation.VisibleForTesting
    suspend fun resetTapHintSeenForTest() { dataStore.edit { it[TAP_HINT_SEEN_KEY] = false } }

    // Each setter takes an optional pre-stamped submission [order]. Concurrent callers (the reader's
    // per-slider launches) MUST pass an order from nextSeq() taken at the synchronous UI callback;
    // sequential callers (tests) may omit it and get an entry-time stamp (order == call order there).
    suspend fun setTheme(theme: ReaderTheme, order: Long = nextSeq()) = update(Field.THEME, order) { it.copy(theme = theme.name) }
    suspend fun setFontFamily(family: ReaderFontFamily, order: Long = nextSeq()) = update(Field.FONT_FAMILY, order) { it.copy(fontFamily = family.name) }
    suspend fun setFontSize(sp: Float, order: Long = nextSeq()) = update(Field.FONT_SIZE, order) { it.copy(fontSizeSp = ReaderSettings.clampFontSize(sp)) }
    suspend fun setLineSpacing(v: Float, order: Long = nextSeq()) = update(Field.LINE_SPACING, order) { it.copy(lineSpacing = ReaderSettings.clampLineSpacing(v)) }
    suspend fun setMargin(dp: Float, order: Long = nextSeq()) = update(Field.MARGIN, order) { it.copy(marginDp = ReaderSettings.clampMargin(dp)) }
    suspend fun setLayout(value: ReaderLayout, order: Long = nextSeq()) = update(Field.LAYOUT, order) { it.copy(layout = value.name) }

    private suspend fun update(field: Field, order: Long, transform: (ReaderSettingsState) -> ReaderSettingsState) {
        writeMutex.withLock {
            // A later-submitted write for THIS field already committed → this one is stale; drop it so
            // the newest value always wins (latest-submission-wins, not last-to-acquire-the-lock).
            if ((committedSeqByField[field] ?: 0L) > order) return@withLock
            // Normalize EVERY numeric field on write (not just the one being set) so a previously
            // hand-edited / older out-of-range value is healed on the next write — truly "clamped on write".
            dataStore.edit { prefs -> prefs[KEY] = json.encodeToString(transform(read(prefs)).normalized()) }
            committedSeqByField[field] = order
        }
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
        layout = runCatching { ReaderLayout.valueOf(layout) }.getOrDefault(ReaderLayout.Scroll),
    )

    companion object {
        private val KEY = stringPreferencesKey("reader_settings_json")
        // feature #137 WI-6b — a SEPARATE key from the display-settings JSON (see tapHintSeen).
        private val TAP_HINT_SEEN_KEY = booleanPreferencesKey("paged_tap_hint_seen")
    }
}
