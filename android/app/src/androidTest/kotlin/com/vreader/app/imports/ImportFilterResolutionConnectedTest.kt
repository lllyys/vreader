// Purpose: feature #155 WI-2 — the AUTHORITATIVE intent-filter matching matrix, run
// against the REAL PackageManager on a device (Gate-2 round 2, M4: Robolectric's
// resolver is a shadow whose PatternMatcher need not reproduce the platform's
// pathPattern behaviour, so the JVM test is structural only and this one decides).
//
// It covers three things the manifest is easy to get silently wrong:
//   1. positive resolution for every shape a real sender uses (VIEW/SEND/SEND_MULTIPLE);
//   2. NEGATIVE space — `SEND` + `image/jpeg` must NOT resolve. A manifest that claimed
//      every MIME type would pass every positive case above while putting VReader in the
//      share sheet for photos;
//   3. `pathPattern` behaviour asserted EMPIRICALLY (PATTERN_SIMPLE_GLOB is not a regex
//      and has no reliable backtracking), including an earlier dot and an uppercase
//      extension. §4's table is corrected to whatever THIS test observes.
package com.vreader.app.imports

import android.content.ComponentName
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import android.net.Uri
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ImportFilterResolutionConnectedTest {

    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private val pm get() = context.packageManager

    /** Does the platform route this intent to ImportActivity, as `startActivity` would? */
    private fun resolves(intent: Intent): Boolean =
        pm.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY).any {
            it.activityInfo.packageName == context.packageName &&
                it.activityInfo.name == IMPORT_ACTIVITY
        }

    /** Every activity OF OURS the platform would offer — proves nothing else caught it. */
    private fun ourMatches(intent: Intent): List<String> =
        pm.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
            .filter { it.activityInfo.packageName == context.packageName }
            .map { it.activityInfo.name }

    private fun view(mime: String, uri: String = CONTENT_URI) =
        Intent(Intent.ACTION_VIEW).setDataAndType(Uri.parse(uri), mime)

    private fun typelessView(uri: String) = Intent(Intent.ACTION_VIEW, Uri.parse(uri))

    private fun send(mime: String) = Intent(Intent.ACTION_SEND).setType(mime)

    private fun sendMultiple(mime: String) = Intent(Intent.ACTION_SEND_MULTIPLE).setType(mime)

    // ---- positive matrix (the plan's §4 acceptance list) ----

    @Test
    fun view_resolvesForEveryDeclaredBookMimeType() {
        listOf(
            "application/epub+zip",
            "application/x-epub+zip",
            "application/epub",
            "application/pdf",
            "application/x-pdf",
            "text/plain",
            "text/markdown",
            "text/x-markdown",
            "application/vnd.amazon.ebook",
            "application/vnd.amazon.mobi8-ebook",
            "application/x-mobipocket-ebook",
            "application/octet-stream",
        ).forEach { mime ->
            assertTrue("VIEW + $mime must resolve to ImportActivity", resolves(view(mime)))
        }
    }

    @Test
    fun view_resolvesForTheFileSchemeToo() {
        // Legacy senders only; a modern sender cannot legally emit file:// at all.
        assertTrue(resolves(view("application/epub+zip", "file:///sdcard/Books/book.epub")))
    }

    @Test
    fun send_resolvesForEpubAndPlainText() {
        assertTrue("SEND + epub", resolves(send("application/epub+zip")))
        assertTrue("SEND + text/plain", resolves(send("text/plain")))
        assertTrue("SEND + octet-stream", resolves(send("application/octet-stream")))
    }

    @Test
    fun sendMultiple_resolvesForPdf() {
        assertTrue(resolves(sendMultiple("application/pdf")))
        assertTrue(resolves(sendMultiple("application/epub+zip")))
    }

    @Test
    fun importActivityIsTheOnlyOneOfOursThatCatchesAnInboundBook() {
        // If a filter ever lands on MainActivity, a VIEW would stack a second
        // MainActivity over an open reader — the exact thing D2 exists to prevent.
        assertEquals(listOf(IMPORT_ACTIVITY), ourMatches(view("application/epub+zip")))
        assertEquals(listOf(IMPORT_ACTIVITY), ourMatches(send("application/pdf")))
    }

    // ---- negative space: the filters must not be over-broad ----

    @Test
    fun send_withAnImageDoesNotResolve() {
        assertFalse("SEND + image/jpeg must NOT resolve", resolves(send("image/jpeg")))
        assertFalse(resolves(sendMultiple("image/jpeg")))
    }

    @Test
    fun undeclaredTypesDoNotResolve() {
        listOf("image/png", "video/mp4", "audio/mpeg", "application/zip", "text/html")
            .forEach { assertFalse("$it must NOT resolve", resolves(send(it))) }
        assertFalse(resolves(view("image/jpeg")))
    }

    @Test
    fun aWildcardINTENTTypeResolves_becauseThePlatformSaysSo_notBecauseWeDeclaredOne() {
        // OBSERVED, and it corrects the plan's §4 expectation. `IntentFilter.findMimeType`
        // special-cases an INTENT whose type is "*/*": it matches any filter declaring a
        // non-empty type list. So a sender that shares with an unknown type offers VReader
        // — as it offers every other app with any typed SEND filter. This is the sender
        // being a wildcard, NOT our filter being one.
        assertTrue(resolves(Intent(Intent.ACTION_SEND).setType("*/*")))
        // The proof our own list is narrow is the concrete undeclared type right below it:
        // if any filter actually declared `*/*`, image/jpeg would resolve too. It does not.
        assertFalse(resolves(send("image/jpeg")))
    }

    // ---- pathPattern, asserted EMPIRICALLY on the platform's PatternMatcher ----

    @Test
    fun typelessView_matchesASimpleBookPath() {
        assertTrue(resolves(typelessView("content://com.example.provider/docs/book.epub")))
    }

    @Test
    fun typelessView_matchesAPathWithAnEarlierDot() {
        // `.*\.epub` alone stops at the FIRST dot and fails here; this is what the extra
        // `.*\.` repeats buy.
        assertTrue(resolves(typelessView("content://com.example.provider/docs/my.book.epub")))
        assertTrue(resolves(typelessView("content://com.example.provider/docs/my.book.v2.epub")))
    }

    @Test
    fun typelessView_matchesAnUppercaseExtension() {
        // pathPattern is case-sensitive, so the uppercase variants must be enumerated.
        assertTrue(resolves(typelessView("content://com.example.provider/docs/BOOK.EPUB")))
        assertTrue(resolves(typelessView("content://com.example.provider/docs/MY.BOOK.PDF")))
    }

    @Test
    fun typelessView_matchesEveryDeclaredExtension() {
        listOf("epub", "pdf", "txt", "md", "markdown", "azw3", "azw", "mobi", "prc")
            .forEach { ext ->
                assertTrue(
                    ".$ext must match",
                    resolves(typelessView("content://com.example.provider/docs/book.$ext")),
                )
            }
    }

    @Test
    fun typelessView_doesNotMatchAnUndeclaredExtension() {
        assertFalse(resolves(typelessView("content://com.example.provider/docs/photo.jpg")))
        assertFalse(resolves(typelessView("content://com.example.provider/docs/archive.zip")))
        assertFalse(resolves(typelessView("content://com.example.provider/docs/noextension")))
    }

    @Test
    fun typelessView_doesNotFallForSuffixTraps() {
        // A pathPattern must match the WHOLE path, so a book extension that is not the
        // LAST segment must not resolve — otherwise `.epub.bak` backups and directory-ish
        // paths would drag VReader in.
        assertFalse(resolves(typelessView("content://com.example.provider/docs/book.epub.bak")))
        assertFalse(resolves(typelessView("content://com.example.provider/docs/book.epub/trailing")))
        assertFalse(resolves(typelessView("content://com.example.provider/docs/epub")))
    }

    @Test
    fun typelessView_overFileSchemeDoesNotMatch() {
        // Documents the M1 correction: file:// has an EMPTY authority, so host="*" can
        // never match it — which is why filter B is content-only.
        assertFalse(resolves(typelessView("file:///sdcard/Books/book.epub")))
    }

    @Test
    fun aTypedViewNeverGoesThroughThePathFilter() {
        // A filter with no mimeType cannot match an intent that HAS one, so an image
        // named `.epub` must not sneak in through filter B.
        assertFalse(resolves(view("image/jpeg", "content://com.example.provider/docs/book.epub")))
    }

    // ---- the declared task model, as the platform actually parsed it ----

    @Test
    fun importActivityIsExportedWithAnIsolatedTaskModel() {
        val info = pm.getActivityInfo(ComponentName(context.packageName, IMPORT_ACTIVITY), 0)
        assertTrue("must be exported", info.exported)
        assertTrue("noHistory", info.flags and ActivityInfo.FLAG_NO_HISTORY != 0)
        assertTrue("excludeFromRecents", info.flags and ActivityInfo.FLAG_EXCLUDE_FROM_RECENTS != 0)
        // taskAffinity="" ⇒ its own affinity-less task, never VReader's.
        assertNotEquals(context.packageName, info.taskAffinity)
        assertTrue("affinity must be empty/null, was ${info.taskAffinity}", info.taskAffinity.isNullOrEmpty())
    }

    private companion object {
        const val IMPORT_ACTIVITY = "com.vreader.app.imports.ImportActivity"
        const val CONTENT_URI = "content://com.example.provider/docs/1"
    }
}
