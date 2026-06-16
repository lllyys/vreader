package vreader.contracts

/**
 * Kotlin reference implementation of vreader's canonical identity contracts
 * (the contracts/identity specs). Mirrors the Swift reference
 * (DocumentFingerprint.swift, ChapterTranslationRecord.swift). The
 * conformance test asserts these produce the SAME outputs as the Swift app
 * for the shared golden vectors — the cross-platform interop gate.
 */
object Identity {
    /** DocumentFingerprint.canonicalKey = "{format}:{contentSHA256}:{fileByteCount}". */
    fun canonicalKey(format: String, contentSHA256: String, fileByteCount: Long): String =
        "$format:$contentSHA256:$fileByteCount"

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
