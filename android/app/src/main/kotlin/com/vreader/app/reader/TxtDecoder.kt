// Purpose: Decode a .txt file's bytes to a String with charset detection — feature
// #111 WI-1 (the Android analog of iOS EncodingDetector). BOM-first (deterministic
// for UTF-8 / UTF-16 LE/BE — the real fixture is UTF-16LE+BOM); BOM-less falls back
// explicitly: strict UTF-8 → a single GBK heuristic (CJK) → UTF-8 with replacement.
// Pure JVM (no Android deps) so it's unit-testable without Robolectric.
package com.vreader.app.reader

import java.io.File
import java.nio.ByteBuffer
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction

/** A decoded text + the charset used + whether detection was confident (BOM / valid strict decode). */
data class TxtDecodeResult(val charsetName: String, val text: String, val confident: Boolean)

object TxtDecoder {
    private val UTF8_BOM = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte())

    fun decode(file: File): TxtDecodeResult = decode(file.readBytes())

    fun decode(bytes: ByteArray): TxtDecodeResult {
        // Empty input has no charset evidence — confident reflects "real charset
        // signal", not merely "decoded without error".
        if (bytes.isEmpty()) return TxtDecodeResult("UTF-8", "", confident = false)
        // 1. BOM — deterministic. Strip the BOM bytes so they don't appear as U+FEFF.
        if (bytes.size >= 3 && bytes[0] == UTF8_BOM[0] && bytes[1] == UTF8_BOM[1] && bytes[2] == UTF8_BOM[2]) {
            return TxtDecodeResult("UTF-8", String(bytes, 3, bytes.size - 3, Charsets.UTF_8), confident = true)
        }
        if (bytes.size >= 2 && bytes[0] == 0xFF.toByte() && bytes[1] == 0xFE.toByte()) {
            return TxtDecodeResult("UTF-16LE", String(bytes, 2, bytes.size - 2, Charsets.UTF_16LE), confident = true)
        }
        if (bytes.size >= 2 && bytes[0] == 0xFE.toByte() && bytes[1] == 0xFF.toByte()) {
            return TxtDecodeResult("UTF-16BE", String(bytes, 2, bytes.size - 2, Charsets.UTF_16BE), confident = true)
        }
        // 2. BOM-less: strict UTF-8 (valid UTF-8 is rarely accidental).
        decodeStrict(bytes, Charsets.UTF_8)?.let { return TxtDecodeResult("UTF-8", it, confident = true) }
        // 3. Single heuristic guess for CJK: GBK (low confidence — decodes most byte
        //    sequences, so it's a guess, not a detection).
        runCatching { Charset.forName("GBK") }.getOrNull()?.let { gbk ->
            decodeStrict(bytes, gbk)?.let { return TxtDecodeResult("GBK", it, confident = false) }
        }
        // 4. Last resort: UTF-8 with replacement (never throws; lossy).
        return TxtDecodeResult("UTF-8", String(bytes, Charsets.UTF_8), confident = false)
    }

    /** Decode strictly (report malformed/unmappable) — returns null if the bytes aren't valid in [charset]. */
    private fun decodeStrict(bytes: ByteArray, charset: Charset): String? = try {
        charset.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT)
            .onUnmappableCharacter(CodingErrorAction.REPORT)
            .decode(ByteBuffer.wrap(bytes))
            .toString()
    } catch (e: Exception) {
        null
    }
}
