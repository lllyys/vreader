// Purpose: feature #116 WI-2 (#110 Phase 3) — the `*.vreader.zip` reader/writer. The ZIP holds
// `metadata.json` + the #113 section JSONs + `library-manifest.json` and carries NO book bytes
// (blobs live in the separate VReader/books/<...> store). Mirrors the iOS WebDAVProvider archive
// step (entry names metadata.json / annotations.json / positions.json / … / library-manifest.json).
// Section content is built by the WI-3 collector; this file only owns the container mechanics +
// metadata/manifest (de)serialization via the #113 `BackupJson` canonical surface.
package com.vreader.app.backup.archive

import vreader.contracts.backup.BackupJson
import vreader.contracts.backup.BackupLibraryManifestEnvelope
import vreader.contracts.backup.BackupMetadata
import vreader.contracts.backup.BackupSchema
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

/** Canonical archive entry names — must match the iOS writer (WebDAVProvider.swift). */
object BackupArchiveEntries {
    const val METADATA = "metadata.json"
    const val MANIFEST = "library-manifest.json"
}

/** A backup ZIP could not be read (malformed container, or the required metadata is missing). */
class BackupArchiveException(message: String, cause: Throwable? = null) : IOException(message, cause)

/**
 * Writes a `*.vreader.zip`: `metadata.json` first, then the section JSONs in [sections] (filename
 * → JSON), then `library-manifest.json`. NO book bytes — the writer rejects any entry that isn't a
 * `.json` (a blob must never ride inside the small ZIP). Returns the container bytes.
 */
object BackupArchiveWriter {
    fun write(
        metadata: BackupMetadata,
        manifest: BackupLibraryManifestEnvelope,
        sections: Map<String, String>,
    ): ByteArray {
        require(sections.keys.none { it == BackupArchiveEntries.METADATA || it == BackupArchiveEntries.MANIFEST }) {
            "metadata/library-manifest are written explicitly, not via the sections map"
        }
        require(sections.keys.all { it.endsWith(".json") }) {
            "the *.vreader.zip carries only JSON sections, never book blobs"
        }
        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { zip ->
            zip.putEntry(BackupArchiveEntries.METADATA, BackupJson.encode(metadata))
            // Stable order so repeat backups of identical content produce identical archives.
            for ((name, json) in sections.toSortedMap()) zip.putEntry(name, json)
            zip.putEntry(BackupArchiveEntries.MANIFEST, BackupJson.encode(manifest))
        }
        return out.toByteArray()
    }

    private fun ZipOutputStream.putEntry(name: String, content: String) {
        putNextEntry(ZipEntry(name))
        write(content.toByteArray(Charsets.UTF_8))
        closeEntry()
    }
}

/**
 * Reads a `*.vreader.zip`. Throws [BackupArchiveException] on a malformed container or a missing
 * `metadata.json`. An absent `library-manifest.json` defaults to an empty schema-1 envelope (iOS
 * parity). Unknown future section files are tolerated — exposed verbatim via [sectionJson], never
 * a hard failure (a v3 reader must accept a vN>3 archive's extra sections).
 */
class BackupArchiveReader private constructor(private val entries: Map<String, ByteArray>) {

    val metadata: BackupMetadata = run {
        val raw = entries[BackupArchiveEntries.METADATA]
            ?: throw BackupArchiveException("backup archive is missing ${BackupArchiveEntries.METADATA}")
        try {
            BackupJson.decode<BackupMetadata>(raw.toString(Charsets.UTF_8))
        } catch (e: Exception) {
            throw BackupArchiveException("backup archive has a malformed ${BackupArchiveEntries.METADATA}", e)
        }
    }

    val manifest: BackupLibraryManifestEnvelope = run {
        val raw = entries[BackupArchiveEntries.MANIFEST]
            ?: return@run BackupLibraryManifestEnvelope(BackupSchema.MANIFEST_SCHEMA_VERSION, emptyList())
        try {
            BackupJson.decode<BackupLibraryManifestEnvelope>(raw.toString(Charsets.UTF_8))
        } catch (e: Exception) {
            throw BackupArchiveException("backup archive has a malformed ${BackupArchiveEntries.MANIFEST}", e)
        }
    }

    /** Every entry name in the archive. */
    val entryNames: Set<String> get() = entries.keys

    /** Raw JSON for a section file, or null if absent (the section was not backed up). */
    fun sectionJson(name: String): String? = entries[name]?.toString(Charsets.UTF_8)

    companion object {
        // The *.vreader.zip carries only metadata + JSON sections (no blobs), so it is normally
        // KB-sized; these caps bound a hostile/corrupt archive's decompressed footprint (ZIP-bomb
        // defence) while staying far above any real backup.
        private const val MAX_ENTRY_BYTES = 64L * 1024 * 1024
        private const val MAX_TOTAL_BYTES = 256L * 1024 * 1024

        fun read(zip: ByteArray): BackupArchiveReader {
            val out = LinkedHashMap<String, ByteArray>()
            try {
                var total = 0L
                ZipInputStream(ByteArrayInputStream(zip)).use { zin ->
                    var entry: ZipEntry? = zin.nextEntry
                    while (entry != null) {
                        if (!entry.isDirectory) {
                            if (out.containsKey(entry.name)) {
                                throw BackupArchiveException("backup archive has a duplicate entry ${entry.name}")
                            }
                            val bytes = readBounded(zin, entry.name, MAX_TOTAL_BYTES - total)
                            total += bytes.size
                            out[entry.name] = bytes
                        }
                        zin.closeEntry()
                        entry = zin.nextEntry
                    }
                }
            } catch (e: BackupArchiveException) {
                throw e
            } catch (e: Exception) {
                throw BackupArchiveException("backup archive is not a readable ZIP", e)
            }
            if (out.isEmpty()) throw BackupArchiveException("backup archive is empty or not a ZIP")
            return BackupArchiveReader(out)
        }

        /** Streams one entry with a hard cap (per-entry AND remaining-total) so a decompression
         *  bomb can't OOM the process before we notice. */
        private fun readBounded(zin: ZipInputStream, name: String, remainingTotal: Long): ByteArray {
            val cap = minOf(MAX_ENTRY_BYTES, remainingTotal)
            val out = ByteArrayOutputStream()
            val buf = ByteArray(64 * 1024)
            var count = 0L
            while (true) {
                val n = zin.read(buf)
                if (n < 0) break
                count += n
                if (count > cap) throw BackupArchiveException("backup archive entry $name exceeds the size limit")
                out.write(buf, 0, n)
            }
            return out.toByteArray()
        }
    }
}
