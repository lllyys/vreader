package com.vreader.app.reader.foliate

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.security.MessageDigest

/**
 * Feature #126 WI-1 — provenance + security-patch guard for the shipped foliate-js bundle.
 *
 * The Android reader hosts the iOS-vendored foliate-js bundle WITH a security patch: `allow-scripts`
 * stripped from every section-iframe sandbox so book-embedded JavaScript cannot execute (WI-0 proved,
 * on-device, that this is the load-bearing boundary — `isMainFrame` alone is insufficient). This test
 * fails the build if:
 *   - the bundle is missing,
 *   - ANY `allow-scripts` survives (a section iframe left unpatched, or a bundle re-copy that dropped
 *     the patch — the partial-patch / drift risk Gate-4 flagged),
 *   - the bytes drift from the pinned patched SHA-256.
 *
 * Source: `vreader/Services/Foliate/JS/foliate-bundle.js` (iOS, SHA-256 3463a2ee…) → strip
 * `allow-same-origin allow-scripts` → `allow-same-origin` (2 occurrences) → this patched bundle.
 */
class FoliateBundleProvenanceTest {

    private val patchedSha = "aa4327f1aac8b4c65a4ca653e53118ca84650887a35e51b0bf7592c4d12aa807"
    private val iosSha = "3463a2ee41168f1549f5ed49fdcfe9eb521dbb5adab3702c63c429838480503d"

    private fun bundleFile(): File {
        // Gradle runs JVM tests with the module dir (android/app) as CWD; fall back to a small upward walk.
        val candidates = listOf(
            "src/main/assets/foliate/foliate-bundle.js",
            "app/src/main/assets/foliate/foliate-bundle.js",
            "android/app/src/main/assets/foliate/foliate-bundle.js",
        )
        return candidates.map { File(it) }.firstOrNull { it.exists() }
            ?: error("foliate-bundle.js not found from CWD=${File(".").absolutePath} (tried $candidates)")
    }

    @Test
    fun shippedBundle_hasNoAllowScripts_inAnySectionIframe() {
        val text = bundleFile().readText()
        val remaining = Regex("allow-scripts").findAll(text).count()
        assertEquals("shipped bundle still has 'allow-scripts' (section iframe(s) unpatched)", 0, remaining)
        // sanity: it is still the foliate bundle (the patched sandbox + the reader API are present).
        assertTrue("bundle missing the patched 'allow-same-origin' sandbox", text.contains("allow-same-origin"))
        assertTrue("bundle missing window.readerAPI", text.contains("readerAPI"))
    }

    @Test
    fun shippedBundle_matchesPinnedPatchedSha() {
        val bytes = bundleFile().readBytes()
        val sha = MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it) }
        assertEquals(
            "shipped foliate-bundle.js drifted from the pinned patched SHA — re-derive from the iOS bundle " +
                "($iosSha) by stripping allow-scripts, and update bundle-patch.md + this pin",
            patchedSha,
            sha,
        )
    }
}
