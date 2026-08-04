package com.vreader.app.diagnostics

/**
 * Purpose: Feature #164 WI-1 — the PURE, JVM-testable half of the logcat source.
 * Turns `logcat -v uid -v threadtime -v year -v UTC` text into [DiagnosticsLogEntry]s.
 *
 * (RED stub — implemented in the GREEN step.)
 */
object LogcatLineParser {

    fun parse(lines: Sequence<String>, ownUid: Int): List<DiagnosticsLogEntry> = emptyList()
}
