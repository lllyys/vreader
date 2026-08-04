package com.vreader.app.diagnostics

/**
 * Purpose: Feature #164 WI-1 — severity of one captured diagnostics entry.
 *
 * Mirrors `android.util.Log`'s priority set exactly as logcat renders it in the
 * `threadtime` format's single-character level column. We do NOT invent levels the
 * platform cannot produce (the iOS analog makes the same call for `Logger.warning()`,
 * which OSLog folds into `.error`).
 *
 * Key decisions:
 * - `S` (SILENT) is a *suppression threshold*, never an emitted entry, so it maps to
 *   `null` alongside every unrecognised character. A caller that gets `null` has a line
 *   that is not a well-formed entry.
 * - `exportTag` is the uppercase token the export payload prints (`[WARN]`); it is a
 *   stored property rather than `name` so a future rename of an enum constant cannot
 *   silently change the on-disk export format.
 *
 * @coordinates-with LogcatLineParser.kt, DiagnosticsLogEntry.kt
 */
enum class DiagnosticsLevel(val priorityChar: Char, val exportTag: String) {
    VERBOSE('V', "VERBOSE"),
    DEBUG('D', "DEBUG"),
    INFO('I', "INFO"),
    WARN('W', "WARN"),
    ERROR('E', "ERROR"),
    ASSERT('F', "ASSERT");

    companion object {
        /** The logcat level column -> our level. `null` for `S` (silent) and anything unknown. */
        fun fromPriorityChar(char: Char): DiagnosticsLevel? = null
    }
}
