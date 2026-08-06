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
 * `allow-same-origin allow-scripts` → `allow-same-origin` (2 occurrences) → THEN the feature #135
 * WI-2 awaited-goTo patch (make `readerAPI.goTo`/`goToFraction` RETURN foliate's `view.goTo(...)`
 * promise so the shell shim can await the relocate + post `goto-ack`) → this patched bundle.
 */
class FoliateBundleProvenanceTest {

    // The pinned SHA of the shipped bundle = iOS bundle, allow-scripts stripped (2×), THEN
    // goTo/goToFraction changed to `return view.goTo(...)`/`return view.goToFraction(...)` (feature #135
    // WI-2). Re-derive by applying BOTH patches; update this pin + bundle-patch.md if the bundle drifts.
    private val patchedSha = "c9b0e101435b1b1757eade7d06633bf7ba382980327574067ae449273e8cf3fa"
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

    /**
     * Feature #142 WI-1 — pin the bridge message names and `readerAPI` members the AZW3 annotation
     * adapter binds to. The SHA pin above already fails on ANY drift, but it says only "the bundle
     * changed"; this says WHICH contract broke. A re-vendored bundle that renamed `annotation-show`
     * or dropped `deleteAnnotation` would otherwise be a green build with silently dead selection.
     */
    @Test
    fun shippedBundle_stillEmitsAndAcceptsTheAnnotationContract() {
        val text = bundleFile().readText()
        // Posted page → native (FoliateMessageParser types all three).
        for (name in listOf("\"selection\"", "\"annotation-show\"", "\"create-overlay\"")) {
            assertTrue("bundle no longer posts $name — the #142 selection path is dead", text.contains(name))
        }
        // Called native → page (feature #142 WI-3 builds the JS for these).
        for (member in listOf("addAnnotation", "deleteAnnotation", "deselect")) {
            assertTrue("bundle no longer exposes readerAPI.$member", text.contains(member))
        }
        // The renderer leg that paints a stored highlight.
        assertTrue("bundle no longer handles draw-annotation", text.contains("draw-annotation"))
        assertTrue("bundle no longer exposes Overlayer.highlight", text.contains("highlight"))
    }

    @Test
    fun shippedBundle_matchesPinnedPatchedSha() {
        val bytes = bundleFile().readBytes()
        val sha = MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it) }
        assertEquals(
            "shipped foliate-bundle.js drifted from the pinned patched SHA — re-derive from the iOS bundle " +
                "($iosSha) by stripping allow-scripts AND applying the #135 WI-2 goTo-return patch, then " +
                "update bundle-patch.md + this pin",
            patchedSha,
            sha,
        )
    }
}
