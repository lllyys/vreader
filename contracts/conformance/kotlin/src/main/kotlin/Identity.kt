package vreader.contracts

/**
 * Kotlin reference implementation of vreader's canonical identity contracts
 * (the contracts/identity specs). Mirrors the Swift reference
 * (DocumentFingerprint.swift, ChapterTranslationRecord.swift). The
 * conformance test asserts these produce the SAME outputs as the Swift app
 * for the shared golden vectors — the cross-platform interop gate.
 */
/** Mirrors Swift `BookFormat: String` (raw values = the case names). */
enum class BookFormat { epub, pdf, txt, md, azw3 }

/** The parsed triple of a canonical key (mirrors `DocumentFingerprint(canonicalKey:)`). */
data class ParsedFingerprint(
    val format: BookFormat,
    val contentSHA256: String,
    val fileByteCount: Long,
)

object Identity {
    /** DocumentFingerprint.canonicalKey = "{format}:{contentSHA256}:{fileByteCount}". */
    fun canonicalKey(format: String, contentSHA256: String, fileByteCount: Long): String =
        "$format:$contentSHA256:$fileByteCount"

    /**
     * Parse a canonical key back to its triple, or null if malformed — mirrors
     * Swift `DocumentFingerprint(canonicalKey:)`: split on ':' into 3 parts
     * (maxSplits 2 — a ':' in the byte-count tail is impossible anyway), a
     * valid `BookFormat` raw value, a non-negative Long byte count, and a valid
     * 64-lowercase-hex sha. Enforces enum-raw-value parity + the same
     * invalid-parse rejections Swift does.
     */
    fun parseCanonicalKey(key: String): ParsedFingerprint? {
        val parts = key.split(":", limit = 3)
        if (parts.size != 3) return null
        val format = BookFormat.entries.firstOrNull { it.name == parts[0] } ?: return null
        val byteCount = parts[2].toLongOrNull() ?: return null
        if (byteCount < 0) return null
        if (!isValidSHA256(parts[1])) return null
        return ParsedFingerprint(format, parts[1], byteCount)
    }

    /** 64 lowercase-hex chars (matches Swift DocumentFingerprint.isValidSHA256). */
    fun isValidSHA256(hex: String): Boolean =
        hex.length == 64 && hex.all { it in '0'..'9' || it in 'a'..'f' }

    /** Validated fingerprint key, or null if invalid (mirrors Swift `validated`). */
    fun validatedCanonicalKey(format: String, contentSHA256: String, fileByteCount: Long): String? =
        if (isValidSHA256(contentSHA256) && fileByteCount >= 0)
            canonicalKey(format, contentSHA256, fileByteCount) else null

    /** ChapterTranslationRecord.lookupKey = book|unit|lang|prompt (provider NOT in key). */
    fun lookupKey(
        bookFingerprintKey: String,
        unitStorageKey: String,
        targetLanguage: String,
        promptVersion: String,
    ): String = listOf(bookFingerprintKey, unitStorageKey, targetLanguage, promptVersion).joinToString("|")
}

/**
 * Canonical Locator serialization — the engine-neutral cross-device-resume
 * contract (mirrors Swift `Locator.canonicalJSON()` in vreader/Models/Locator.swift).
 * Sorted keys, nil omission, bookFingerprint inlined with prefix, floats `%.6f`
 * (POSIX/US locale), CR-LF / CR normalized to LF, RFC-8259 escaping. Produces a
 * byte-identical string to the Swift reference for the same logical position ->
 * identical canonicalHash -> cross-platform position identity (feature #104).
 */
object CanonicalLocator {
    /** All fields optional except the bookFingerprint triple (always present). */
    fun canonicalJson(
        contentSHA256: String,
        fileByteCount: Long,
        format: String,
        cfi: String? = null,
        charOffsetUTF16: Int? = null,
        charRangeEndUTF16: Int? = null,
        charRangeStartUTF16: Int? = null,
        href: String? = null,
        page: Int? = null,
        progression: Double? = null,
        textContextAfter: String? = null,
        textContextBefore: String? = null,
        textQuote: String? = null,
        totalProgression: Double? = null,
    ): String {
        val pairs = ArrayList<Pair<String, String>>()
        pairs.add("bookFingerprint.contentSHA256" to jsonQuoted(contentSHA256))
        pairs.add("bookFingerprint.fileByteCount" to fileByteCount.toString())
        pairs.add("bookFingerprint.format" to jsonQuoted(format))
        if (cfi != null) pairs.add("cfi" to jsonQuoted(cfi))
        if (charOffsetUTF16 != null) pairs.add("charOffsetUTF16" to charOffsetUTF16.toString())
        if (charRangeEndUTF16 != null) pairs.add("charRangeEndUTF16" to charRangeEndUTF16.toString())
        if (charRangeStartUTF16 != null) pairs.add("charRangeStartUTF16" to charRangeStartUTF16.toString())
        if (href != null) pairs.add("href" to jsonQuoted(href))
        if (page != null) pairs.add("page" to page.toString())
        if (progression != null && progression.isFinite()) pairs.add("progression" to rounded(progression))
        if (textContextAfter != null) pairs.add("textContextAfter" to jsonQuoted(normalizeLineEndings(textContextAfter)))
        if (textContextBefore != null) pairs.add("textContextBefore" to jsonQuoted(normalizeLineEndings(textContextBefore)))
        if (textQuote != null) pairs.add("textQuote" to jsonQuoted(normalizeLineEndings(textQuote)))
        if (totalProgression != null && totalProgression.isFinite()) pairs.add("totalProgression" to rounded(totalProgression))

        pairs.sortBy { it.first }
        return pairs.joinToString(",", prefix = "{", postfix = "}") { "\"${it.first}\":${it.second}" }
    }

    /** RFC-8259 escaping (matches Swift jsonQuoted): quote, backslash, \n \r \t, control -> \uXXXX. */
    private fun jsonQuoted(s: String): String {
        val sb = StringBuilder("\"")
        for (ch in s) {
            when (ch) {
                '"' -> sb.append("\\\"")
                '\\' -> sb.append("\\\\")
                '\n' -> sb.append("\\n")
                '\r' -> sb.append("\\r")
                '\t' -> sb.append("\\t")
                else -> if (ch.code < 0x20) sb.append("\\u%04x".format(ch.code)) else sb.append(ch)
            }
        }
        return sb.append("\"").toString()
    }

    /** POSIX/US-locale %.6f (matches Swift roundedString). */
    private fun rounded(value: Double): String = "%.6f".format(java.util.Locale.US, value)

    private fun normalizeLineEndings(s: String): String =
        s.replace("\r\n", "\n").replace("\r", "\n")
}
