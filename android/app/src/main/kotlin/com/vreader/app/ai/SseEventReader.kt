// Purpose: feature #118 WI-2 (#110 Phase 3) — a shared, BOUNDED Server-Sent-Events framer. Reads a
// text/event-stream line-by-line and yields COMPLETE events (the per-provider payload parsers then
// interpret each event's data). Handles the SSE wire rules that both OpenAI and Anthropic streams
// rely on: blank-line event boundaries, `:`-comment/keepalive lines, multiple `data:` lines per
// event (joined with '\n'), and an `event:` type line (Anthropic). Bounded so a hostile/endless
// provider stream can't OOM: a single line and a single accumulated event are capped.
package com.vreader.app.ai

import java.io.BufferedReader
import java.io.InputStream

/** One framed SSE event: its optional `event:` type + the concatenated `data:` payload. */
data class SseEvent(val event: String?, val data: String)

object SseEventReader {
    const val MAX_LINE_BYTES = 64 * 1024
    const val MAX_EVENT_BYTES = 256 * 1024

    /**
     * Lazily frames [input] (UTF-8) into complete [SseEvent]s. The sequence ends at EOF. Throws
     * [AiError.Stream] if a single line or event exceeds the cap. The caller drives consumption and
     * closes [input] (closing it mid-iteration cancels the stream — the provider does that on Flow
     * cancellation).
     */
    fun events(input: InputStream): Sequence<SseEvent> = sequence {
        val reader = input.bufferedReader(Charsets.UTF_8)
        val data = StringBuilder()
        var eventType: String? = null
        var eventBytes = 0

        fun flush(): SseEvent? {
            if (data.isEmpty() && eventType == null) return null
            val ev = SseEvent(eventType, data.toString())
            data.setLength(0); eventType = null; eventBytes = 0
            return ev
        }

        while (true) {
            val line = readLineBounded(reader) ?: break  // EOF
            when {
                line.isEmpty() -> flush()?.let { yield(it) }          // event boundary
                line.startsWith(":") -> Unit                          // comment / keepalive — skip
                line.startsWith("data:") -> {
                    val piece = line.removePrefix("data:").removePrefix(" ")
                    eventBytes += piece.toByteArray(Charsets.UTF_8).size + 1
                    if (eventBytes > MAX_EVENT_BYTES) throw AiError.Stream("event exceeds the size limit")
                    if (data.isNotEmpty()) data.append('\n')
                    data.append(piece)
                }
                line.startsWith("event:") -> eventType = line.removePrefix("event:").removePrefix(" ").trim()
                // other field lines (id:, retry:) — ignored for our use
            }
        }
        flush()?.let { yield(it) }  // a final event with no trailing blank line
    }

    /** Read one line, rejecting an over-long line before it can OOM (a stream with no newlines). */
    private fun readLineBounded(reader: BufferedReader): String? {
        val sb = StringBuilder()
        while (true) {
            val c = reader.read()
            if (c == -1) return if (sb.isEmpty()) null else sb.toString()
            if (c == '\n'.code) return sb.toString().removeSuffix("\r")
            sb.append(c.toChar())
            if (sb.length > MAX_LINE_BYTES) throw AiError.Stream("line exceeds the size limit")
        }
    }
}
