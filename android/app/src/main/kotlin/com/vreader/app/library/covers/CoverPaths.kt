// Purpose: feature #152 WI-1 — where a book's extracted cover lives on disk, and the guard that
// says whether one is there. Pure `java.io`: no Android types, no bitmaps.
//
// Key decisions:
// - **Split from the bitmap I/O on purpose.** Robolectric's `Bitmap`/`compress` are shadows, so
//   encode + downscale assertions are untrustworthy in the JVM lane. Keeping paths and guards in
//   a type with no Android surface puts them in the fast lane and leaves only the genuinely
//   pixel-dependent assertions to the connected one (WI-6's `CoverStore`).
// - **`hasCover` requires a non-empty REGULAR file.** A kill mid-write leaves a zero-length file;
//   calling that "has a cover" would pin it forever, since WI-6's `saveIfAbsent` declines to
//   overwrite an existing cover and the decoder would render nothing. A directory at the path is
//   pathological and reports non-zero `length()` on some filesystems, so `isFile` is the check,
//   not `exists()`.
// - **The canonical-key precondition is asserted HERE, at every entry point.** This type turns an
//   untyped String into a filesystem path, so it is the boundary where `StorageNaming`'s
//   frozen-but-domain-limited mapping stops being safe by assumption. Every production key comes
//   from `Book.fingerprintKey`, which only `BookImporter` writes and only ever as
//   `Identity.canonicalKey(...)` — so the `require` cannot fire on a real path, and firing means a
//   programmer error, not a user-reachable state.
// - **Never creates the directory.** WI-6 owns `filesDir/covers` creation; a missing root simply
//   means no covers yet.
//
// @coordinates-with: ../../data/StorageNaming.kt, CoverResult.kt
package com.vreader.app.library.covers

import com.vreader.app.data.StorageNaming
import vreader.contracts.Identity
import java.io.File

/**
 * Resolves and probes cover files under [root] (`filesDir/covers`).
 *
 * @throws IllegalArgumentException if a key is not a canonical fingerprint key.
 */
class CoverPaths(private val root: File) {

    /** `<root>/<sanitised key>.jpg` — the one place the cover's path is composed. */
    fun coverFile(fingerprintKey: String): File {
        require(Identity.parseCanonicalKey(fingerprintKey) != null) {
            "cover key is not a canonical fingerprint key"
        }
        return File(root, "${StorageNaming.fileNameForKey(fingerprintKey)}.jpg")
    }

    /** True only for a regular file with bytes in it — a zero-length residue is NOT a cover. */
    fun hasCover(fingerprintKey: String): Boolean =
        coverFile(fingerprintKey).let { it.isFile && it.length() > 0L }

    /** Deletes the cover if present. A missing file is a no-op; never throws. */
    fun remove(fingerprintKey: String) {
        coverFile(fingerprintKey).delete()
    }
}
