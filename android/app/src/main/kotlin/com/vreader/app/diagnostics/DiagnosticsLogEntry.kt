package com.vreader.app.diagnostics

/**
 * Purpose: Feature #164 WI-1 — value type for one captured diagnostics log entry
 * (the iOS `DiagnosticsLogEntry` analog, ported in shape, not in OSLog mechanics).
 *
 * Key decisions:
 * - `timeMillis` is epoch millis. The parser derives it from the line's own explicit
 *   UTC offset, so no ambient timezone can shift a captured entry.
 * - `category` is the raw logcat tag, trimmed; `""` when the tag column was absent.
 *   Mapping raw tags onto the design's bounded category vocabulary is a LATER concern
 *   (WI-3's `DiagnosticsCategory` / the chip-bounding rule) — this type stays raw.
 * - `message` may be multi-line (a stack trace arrives as continuation lines) and has
 *   the VLog marker ALREADY STRIPPED — see [VLogMarker]. Nothing downstream (viewer,
 *   export) should ever have to know the marker exists.
 * - `sequenceId` is the identity the composite source dedupes on. `null` means "not a
 *   VLog-originated entry" (framework/library line, or a marker that failed to parse);
 *   dedupe therefore never drops an entry it cannot positively identify.
 *
 * @coordinates-with LogcatLineParser.kt, DiagnosticsLogSource.kt, DiagnosticsLevel.kt
 */
data class DiagnosticsLogEntry(
    val timeMillis: Long,
    val level: DiagnosticsLevel,
    val category: String,
    val message: String,
    val sequenceId: Long? = null,
)

/**
 * The compact leading token VLog (WI-3) stamps onto every `android.util.Log` message so a
 * logcat-read entry can be matched back to its ring-buffer twin.
 *
 * Why a LEADING token: logd truncates an over-long payload at the TAIL (max payload 4068 B),
 * so a leading marker cannot be destroyed by truncation. Guillemets are used because they do
 * not occur in this app's own log vocabulary and need no escaping.
 *
 * A malformed marker (`«v»`, `«vabc»`, an id that overflows `Long`) is ordinary message text:
 * the parser leaves it in place and reports `sequenceId == null`. Failing open on retention is
 * deliberate — a mis-stripped message is a data loss, an un-stripped one is only cosmetic and
 * is caught by the "no entry retains a marker" assertion.
 */
object VLogMarker {
    const val OPEN: String = "«v"
    const val CLOSE: String = "»"

    /** `«v42»` — what VLog prepends. */
    fun encode(sequenceId: Long): String = "$OPEN$sequenceId$CLOSE"
}
