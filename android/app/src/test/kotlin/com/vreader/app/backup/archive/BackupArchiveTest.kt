package com.vreader.app.backup.archive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import vreader.contracts.backup.BackupJson
import vreader.contracts.backup.BackupLibraryEntry
import vreader.contracts.backup.BackupLibraryManifestEnvelope
import vreader.contracts.backup.BackupMetadata
import java.time.Instant
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/**
 * Feature #116 WI-2 — the `*.vreader.zip` round-trip + the BlobPath layout. Verifies the archive
 * carries metadata + sections + manifest and NO book bytes, tolerates an unknown future section,
 * and rejects a malformed / metadata-less container; BlobPath matches the iOS layout.
 */
class BackupArchiveTest {

    private fun metadata(books: Int = 1) = BackupMetadata(
        id = "11111111-1111-4111-8111-111111111111",
        createdAt = Instant.parse("2026-06-20T12:00:00Z"),
        deviceName = "Pixel 7",
        appVersion = "0.7.1",
        bookCount = books,
        totalSizeBytes = 4096,
    )

    private fun manifest(title: String = "Moby Dick") = BackupLibraryManifestEnvelope(
        schemaVersion = 1,
        books = listOf(
            BackupLibraryEntry(
                fingerprintKey = "epub:" + "a".repeat(64) + ":1024",
                format = "epub",
                sha256 = "a".repeat(64),
                byteCount = 1024,
                originalExtension = "epub",
                title = title,
                addedAt = Instant.parse("2026-06-01T00:00:00Z"),
                blobPath = BlobPath.make(vreader.contracts.BookFormat.epub, "a".repeat(64), 1024),
            )
        ),
    )

    @Test fun writeThenRead_roundTrips_metadata_sections_manifest() {
        val positions = """{"schemaVersion":3,"positions":[]}"""
        val zip = BackupArchiveWriter.write(
            metadata(), manifest(),
            sections = mapOf("positions.json" to positions, "annotations.json" to "{}"),
        )
        val reader = BackupArchiveReader.read(zip)
        assertEquals("Pixel 7", reader.metadata.deviceName)
        assertEquals(1, reader.manifest.books.size)
        assertEquals("Moby Dick", reader.manifest.books[0].title)
        assertEquals(positions, reader.sectionJson("positions.json"))
        assertEquals("{}", reader.sectionJson("annotations.json"))
    }

    @Test fun archive_carriesNoBookBytes_onlyJson() {
        val zip = BackupArchiveWriter.write(metadata(), manifest(), mapOf("positions.json" to "{}"))
        val reader = BackupArchiveReader.read(zip)
        assertTrue("every entry is a .json", reader.entryNames.all { it.endsWith(".json") })
        // The blob path is recorded in the manifest, never materialized into the ZIP.
        assertTrue(reader.manifest.books[0].blobPath.startsWith("VReader/books/epub/"))
        assertNull(reader.sectionJson(reader.manifest.books[0].blobPath))
    }

    @Test fun writer_rejectsNonJsonSection() {
        assertThrows(IllegalArgumentException::class.java) {
            BackupArchiveWriter.write(metadata(), manifest(), mapOf("cover.png" to "x"))
        }
    }

    @Test fun reader_tolerates_unknownFutureSection() {
        // Hand-build a ZIP with metadata + a vN>3 section name the current reader doesn't know.
        val zip = rawZip(
            "metadata.json" to BackupJson.encode(metadata()),
            "future-thing.json" to """{"schemaVersion":9}""",
        )
        val reader = BackupArchiveReader.read(zip)
        assertEquals("Pixel 7", reader.metadata.deviceName)
        assertEquals("""{"schemaVersion":9}""", reader.sectionJson("future-thing.json"))
        // Manifest absent → empty schema-1 envelope (iOS parity), not a failure.
        assertEquals(1, reader.manifest.schemaVersion)
        assertTrue(reader.manifest.books.isEmpty())
    }

    @Test fun reader_throwsOnMissingMetadata() {
        val zip = rawZip("positions.json" to "{}")
        assertThrows(BackupArchiveException::class.java) { BackupArchiveReader.read(zip) }
    }

    @Test fun reader_throwsOnMalformedZip() {
        assertThrows(BackupArchiveException::class.java) {
            BackupArchiveReader.read("not a zip at all".toByteArray())
        }
    }

    @Test fun reader_throwsOnDuplicateEntry() {
        // ZipOutputStream refuses to WRITE a duplicate name, so build a 2nd entry under a
        // same-length placeholder, then rename it in the raw bytes (equal length keeps every ZIP
        // offset valid). ZipInputStream reads local headers sequentially → two metadata.json.
        val placeholder = "zz_dup_zz.bin"  // 13 bytes == "metadata.json".length
        val raw = rawZip(
            "metadata.json" to BackupJson.encode(metadata()),
            placeholder to "dup",
        )
        val zip = replaceBytes(raw, placeholder.toByteArray(), "metadata.json".toByteArray())
        assertThrows(BackupArchiveException::class.java) { BackupArchiveReader.read(zip) }
    }

    private fun replaceBytes(data: ByteArray, from: ByteArray, to: ByteArray): ByteArray {
        require(from.size == to.size)
        val out = data.copyOf()
        var i = 0
        while (i <= out.size - from.size) {
            if ((0 until from.size).all { out[i + it] == from[it] }) {
                for (j in to.indices) out[i + j] = to[j]
                i += from.size
            } else i++
        }
        return out
    }

    @Test fun roundTrips_cjkTitle() {
        val zip = BackupArchiveWriter.write(metadata(), manifest(title = "红楼梦 · 第一回"), mapOf("positions.json" to "{}"))
        val reader = BackupArchiveReader.read(zip)
        assertEquals("红楼梦 · 第一回", reader.manifest.books[0].title)
    }

    @Test fun blobPath_matchesIosLayout_andRoundTrips() {
        val sha = "b".repeat(64)
        val p = BlobPath.make(vreader.contracts.BookFormat.azw3, sha, 2048)
        assertEquals("VReader/books/azw3/${sha}_2048.azw3", p)
        val parsed = BlobPath.parse(p)
        assertEquals(vreader.contracts.BookFormat.azw3, parsed!!.first)
        assertEquals(sha, parsed.second)
        assertEquals(2048L, parsed.third)
        assertNull("rejects a bad sha", BlobPath.parse("VReader/books/epub/short_10.epub"))
        assertNull("rejects an unknown format", BlobPath.parse("VReader/books/rtf/${sha}_10.rtf"))
        // Extension must be the format's canonical ext — a mismatched ext is not our layout.
        assertNull("rejects ext≠format", BlobPath.parse("VReader/books/epub/${sha}_10.pdf"))
        assertNull("rejects azw3 dir with .mobi ext", BlobPath.parse("VReader/books/azw3/${sha}_10.mobi"))
    }

    private fun rawZip(vararg entries: Pair<String, String>): ByteArray {
        val out = java.io.ByteArrayOutputStream()
        ZipOutputStream(out).use { z ->
            for ((name, content) in entries) {
                z.putNextEntry(ZipEntry(name)); z.write(content.toByteArray()); z.closeEntry()
            }
        }
        return out.toByteArray()
    }
}
