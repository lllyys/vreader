// Purpose: feature #152 WI-1 — the ONE key→filename sanitisation shared by every on-disk store
// (book artifacts in `filesDir/books`, cover art in `filesDir/covers`). Extracted from
// `BookImporter`'s former private `fileNameForKey` so the two stores provably share one scheme:
// a comment claiming they agree is not the same thing as calling the same function.
//
// Key decisions:
// - **The mapping is FROZEN.** It already names every book artifact on every user's device, and
//   `BookEntity.localFilePath` points at those names. Changing it — the substitution character,
//   the safe-character class, appending a hash — silently orphans every existing library. This is
//   an extraction, never a redesign; `StorageNamingTest` pins the literal output.
// - **Injective on the canonical-key domain ONLY, and that is enough.** `a:b` and `a/b` both map
//   to `a_b`, so this is not a general-purpose escaper. On the declared domain the collision is
//   unreachable: `Identity.canonicalKey` emits `{format}:{64-lowercase-hex}:{non-negative Long}`,
//   in which the only characters outside `[A-Za-z0-9._-]` are the two ':' at structurally fixed
//   positions — so ':'→'_' is invertible there, hence injective.
// - **No precondition check HERE.** This stays a total function so extracting it changes
//   `BookImporter`'s behaviour in no way at all, including which exceptions it can throw. The
//   store that derives a filesystem path from an untyped String — `CoverPaths` — is where the
//   precondition is asserted.
//
// @coordinates-with: BookImporter.kt, ../library/covers/CoverPaths.kt
package com.vreader.app.data

/**
 * Maps a fingerprint key to a filesystem-safe file name.
 *
 * PRECONDITION: [key] is a canonical fingerprint key — exactly an `Identity.canonicalKey` output.
 * The mapping is injective on that domain only; callers that accept a key from outside the
 * library (a path, user input, a manifest field) must validate it before calling. `CoverPaths`
 * does; `BookImporter` does not need to, because it names the key it just computed.
 */
internal object StorageNaming {
    private val UNSAFE = Regex("[^A-Za-z0-9._-]")

    fun fileNameForKey(key: String): String = key.replace(UNSAFE, "_")
}
