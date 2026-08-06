package com.vreader.app.library.covers

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

/**
 * Feature #152 WI-1 — the cover store's path/guard layer.
 *
 * Split out of the bitmap I/O deliberately: Robolectric's `Bitmap`/`compress` are shadows, so
 * encode + downscale assertions are not trustworthy in the JVM lane and belong to the connected
 * one. Everything here is `java.io` only, so it means what it says.
 *
 * `hasCover` is the guard WI-6's `saveIfAbsent` and the #153 user pick both consult, and WI-6's
 * orphan sweep is the only caller of `remove`; both must be honest about a half-written file and
 * both must be safe to call for a book that has no cover at all.
 */
class CoverPathsTest {
    @get:Rule val tmp = TemporaryFolder()

    private val key = "epub:$SHA_A:4096"
    private val otherKey = "azw3:$SHA_B:6288371"

    @Test fun coverFile_isAJpgDirectlyInsideRoot() {
        val root = tmp.newFolder("covers")
        val file = CoverPaths(root).coverFile(key)
        assertEquals(root, file.parentFile)
        assertEquals("epub_${SHA_A}_4096.jpg", file.name)
    }

    /** WI-6 creates the directory; [CoverPaths] must not require it to exist to answer. */
    @Test fun worksBeforeTheRootDirectoryExists() {
        val root = File(tmp.newFolder("app"), "covers")
        assertFalse(root.exists())
        val paths = CoverPaths(root)
        assertEquals(root, paths.coverFile(key).parentFile)
        assertFalse(paths.hasCover(key))
        paths.remove(key) // no-op, never throws
        assertFalse(root.exists())
    }

    @Test fun hasCover_isFalseBeforeAnythingIsWritten() {
        assertFalse(CoverPaths(tmp.newFolder("covers")).hasCover(key))
    }

    @Test fun hasCover_isTrueForANonEmptyFile() {
        val paths = CoverPaths(tmp.newFolder("covers"))
        paths.coverFile(key).writeBytes(byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte()))
        assertTrue(paths.hasCover(key))
    }

    /**
     * A zero-length file is what a kill mid-write leaves behind. Treating it as "has a cover"
     * would permanently pin an empty file: `saveIfAbsent` would decline to overwrite it and the
     * decoder would render nothing, forever.
     */
    @Test fun hasCover_isFalseForAZeroLengthFile() {
        val paths = CoverPaths(tmp.newFolder("covers"))
        assertTrue(paths.coverFile(key).createNewFile())
        assertTrue(paths.coverFile(key).exists())
        assertFalse(paths.hasCover(key))
    }

    /** A directory at the cover's path has a non-zero `length()` on some filesystems. */
    @Test fun hasCover_isFalseWhenThePathIsADirectory() {
        val paths = CoverPaths(tmp.newFolder("covers"))
        assertTrue(paths.coverFile(key).mkdirs())
        assertFalse(paths.hasCover(key))
    }

    @Test fun remove_deletesTheCover() {
        val paths = CoverPaths(tmp.newFolder("covers"))
        paths.coverFile(key).writeBytes(byteArrayOf(1, 2, 3))
        paths.remove(key)
        assertFalse(paths.coverFile(key).exists())
        assertFalse(paths.hasCover(key))
    }

    @Test fun remove_isIdempotentAndNeverThrowsForAMissingFile() {
        val paths = CoverPaths(tmp.newFolder("covers"))
        paths.remove(key)
        paths.coverFile(key).writeBytes(byteArrayOf(1))
        paths.remove(key)
        paths.remove(key)
        assertFalse(paths.coverFile(key).exists())
    }

    @Test fun remove_alsoClearsAZeroLengthResidue() {
        val paths = CoverPaths(tmp.newFolder("covers"))
        paths.coverFile(key).createNewFile()
        paths.remove(key)
        assertFalse(paths.coverFile(key).exists())
    }

    @Test fun remove_leavesOtherBooksCoversAlone() {
        val paths = CoverPaths(tmp.newFolder("covers"))
        paths.coverFile(key).writeBytes(byteArrayOf(1))
        paths.coverFile(otherKey).writeBytes(byteArrayOf(2))
        paths.remove(key)
        assertFalse(paths.hasCover(key))
        assertTrue(paths.hasCover(otherKey))
    }

    @Test fun distinctCanonicalKeysGetDistinctFiles() {
        val paths = CoverPaths(tmp.newFolder("covers"))
        assertFalse(paths.coverFile(key).name == paths.coverFile(otherKey).name)
    }

    /**
     * The precondition is enforced at EVERY entry point, not only the one that returns the path —
     * `hasCover` and `remove` derive the same path and must not accept a key `coverFile` rejects.
     */
    @Test fun everyEntryPointRejectsANonCanonicalKey() {
        val paths = CoverPaths(tmp.newFolder("covers"))
        val bad = "../../etc/passwd"
        assertThrowsIllegalArgument { paths.coverFile(bad) }
        assertThrowsIllegalArgument { paths.hasCover(bad) }
        assertThrowsIllegalArgument { paths.remove(bad) }
    }

    private fun assertThrowsIllegalArgument(body: () -> Unit) {
        try {
            body()
            throw AssertionError("expected IllegalArgumentException")
        } catch (expected: IllegalArgumentException) {
            // expected
        }
    }

    private companion object {
        const val SHA_A = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
        const val SHA_B = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    }
}
