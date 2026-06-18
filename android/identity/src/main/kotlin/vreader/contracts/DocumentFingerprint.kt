package vreader.contracts

import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.security.MessageDigest

/**
 * Content-based document identity — SHA-256 over the exact imported bytes + the
 * byte count + the format, the canonical dedup key across the library. Mirrors the
 * Swift `DocumentFingerprint` (vreader/Models/DocumentFingerprint.swift); the key
 * string composition is shared with [Identity.canonicalKey] and asserted by the
 * conformance lane. Pure JVM (no Android deps) so it lives in `:identity` and runs
 * in both the app build and the conformance lane.
 *
 * The hash is over the LOCAL artifact's bytes — converter-independent identity
 * (feature #106 Gate-2 High-2): copy the source bytes into app-private storage and
 * fingerprint THOSE, never a re-converted form.
 */
object DocumentFingerprint {
    /** A computed fingerprint: the SHA-256 hex + byte count, pairs with a format → key. */
    data class Result(val sha256: String, val fileByteCount: Long) {
        fun canonicalKey(format: BookFormat): String =
            Identity.canonicalKey(format.name, sha256, fileByteCount)
    }

    /**
     * Streams [input] in 64KB chunks, optionally tee-ing the bytes into [sink], and
     * returns the SHA-256 (64 lowercase hex) + byte count. Single pass: when [sink]
     * is the destination file's stream, the bytes hashed are exactly the bytes
     * written, so the fingerprint is of the stored local artifact. Does NOT close
     * [input] or [sink] — the caller owns both (consistent ownership across all
     * call sites).
     */
    fun hashing(input: InputStream, sink: OutputStream? = null): Result {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(64 * 1024)
        var total = 0L
        while (true) {
            val read = input.read(buffer)
            if (read < 0) break
            digest.update(buffer, 0, read)
            sink?.write(buffer, 0, read)
            total += read
        }
        sink?.flush()
        val hex = digest.digest().joinToString("") { "%02x".format(it) }
        return Result(hex, total)
    }

    /** Fingerprints an on-disk file (re-reads it; used to re-assert identity after a copy). */
    fun hash(file: File): Result = file.inputStream().buffered().use { hashing(it) }

    /**
     * Maps a filename to its [BookFormat] by extension, or null if unsupported.
     * `azw3`/`azw`/`mobi`/`prc` all canonicalize to `azw3` (the Kindle/KF8 family,
     * matching the iOS dispatch).
     */
    fun formatForFilename(name: String): BookFormat? =
        when (name.substringAfterLast('.', "").lowercase()) {
            "epub" -> BookFormat.epub
            "pdf" -> BookFormat.pdf
            "txt" -> BookFormat.txt
            "md", "markdown" -> BookFormat.md
            "azw3", "azw", "mobi", "prc" -> BookFormat.azw3
            else -> null
        }
}
