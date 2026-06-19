// Purpose: Addressable, range-based model of a decoded .txt — feature #111 WI-1.
// Holds ONE backing decoded String and an array of chunk START offsets (UTF-16 code
// units against the RAW text — NO line-ending normalization, so charOffsetUTF16 stays
// exact for resume). Splits at line boundaries (CRLF/CR/LF kept inside the chunk);
// hard-splits a runaway line at maxChunkChars (never mid-surrogate-pair). Visible
// chunk text is materialized on demand (no per-chunk substrings retained). Pure JVM.
package com.vreader.app.reader

class TxtDocument private constructor(
    val text: String,
    private val starts: IntArray,
) {
    /** Number of chunks (0 for empty text). */
    val chunkCount: Int get() = starts.size

    /** The UTF-16 start offset of chunk [index] (clamped to a valid chunk). */
    fun offsetForChunk(index: Int): Int {
        if (starts.isEmpty()) return 0
        return starts[index.coerceIn(0, starts.size - 1)]
    }

    /** The chunk index containing [offsetUtf16] (EOF-clamped); 0 for empty text. */
    fun chunkForOffset(offsetUtf16: Int): Int {
        if (starts.isEmpty()) return 0
        val offset = offsetUtf16.coerceIn(0, text.length)
        // Largest start <= offset (binary search).
        var lo = 0; var hi = starts.size - 1; var ans = 0
        while (lo <= hi) {
            val mid = (lo + hi) ushr 1
            if (starts[mid] <= offset) { ans = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return ans
    }

    /** The text of chunk [index], materialized on demand from the backing string. */
    fun textForChunk(index: Int): CharSequence {
        if (starts.isEmpty()) return ""
        val i = index.coerceIn(0, starts.size - 1)
        val end = if (i + 1 < starts.size) starts[i + 1] else text.length
        return text.subSequence(starts[i], end)
    }

    companion object {
        const val DEFAULT_MAX_CHUNK_CHARS = 4000

        /**
         * Build a document from already-decoded [text]. Chunk boundaries fall after a
         * line terminator (`\n`, `\r`, or `\r\n` — preserved in the chunk); a line longer
         * than [maxChunkChars] is hard-split, but never between a surrogate pair.
         */
        fun of(text: String, maxChunkChars: Int = DEFAULT_MAX_CHUNK_CHARS): TxtDocument {
            if (text.isEmpty()) return TxtDocument(text, IntArray(0))
            // Primitive growable IntArray (no Int boxing) — a newline-dense 14MB file
            // would otherwise spike tens of MB of boxed Integers + a duplicating copy.
            var starts = IntArray(64)
            var count = 0
            fun push(v: Int) {
                if (count == starts.size) starts = starts.copyOf(starts.size * 2)
                starts[count++] = v
            }
            push(0)
            var i = 0
            var chunkStart = 0
            val n = text.length
            while (i < n) {
                val c = text[i]
                when {
                    c == '\n' -> {
                        i++
                        if (i < n) { push(i); chunkStart = i }
                    }
                    c == '\r' -> {
                        i++
                        if (i < n && text[i] == '\n') i++   // CRLF stays one terminator
                        if (i < n) { push(i); chunkStart = i }
                    }
                    else -> {
                        i++
                        // Hard-split a runaway line, but not mid-surrogate-pair (don't
                        // split right after a high surrogate — its low half follows at i).
                        if (i - chunkStart >= maxChunkChars && i < n && !text[i - 1].isHighSurrogate()) {
                            push(i); chunkStart = i
                        }
                    }
                }
            }
            return TxtDocument(text, starts.copyOf(count))
        }
    }
}
