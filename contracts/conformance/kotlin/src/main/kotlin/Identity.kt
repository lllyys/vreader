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
