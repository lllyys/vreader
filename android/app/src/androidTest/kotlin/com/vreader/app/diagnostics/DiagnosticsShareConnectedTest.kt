// Purpose: feature #164 WI-7 — the parts of the export/share path that only a REAL device can
// answer: whether the manifest's second `<provider>` actually resolves, whether it is scoped to
// `filesDir/diagnostics` and nothing else, and whether the book provider's grant scope is still
// exactly `filesDir/books` afterwards.
//
// The negative provider test is the point of this file. The positive one would pass identically if
// the implementation had widened `@xml/file_paths` instead of adding a provider — it discriminates
// nothing on its own. Asking the BOOK authority for the export file and requiring
// IllegalArgumentException is what actually asserts the section 6.4 invariant, and the book-file
// positive control beside it rules out the degenerate "the book provider is simply broken" reading.
package com.vreader.app.diagnostics

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.system.ErrnoException
import android.system.Os
import androidx.core.content.FileProvider
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assume
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.nio.charset.StandardCharsets
import java.util.UUID

@RunWith(AndroidJUnit4::class)
class DiagnosticsShareConnectedTest {

    private companion object {
        const val DIAGNOSTICS_AUTHORITY = "com.vreader.app.diagnosticsprovider"
        const val BOOK_AUTHORITY = "com.vreader.app.fileprovider"
    }

    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private val diagnosticsDir: File get() = File(context.filesDir, DiagnosticsExportWriter.DIRECTORY_NAME)
    private val booksDir: File get() = File(context.filesDir, "books")

    private lateinit var strays: MutableList<File>

    @Before fun setUp() {
        strays = mutableListOf()
        // The app id must be un-suffixed for the literal authorities above to be the real ones —
        // assert it rather than deriving, so a future applicationIdSuffix fails loudly here.
        assertEquals("com.vreader.app", context.packageName)
    }

    @After fun tearDown() {
        strays.forEach { it.delete() }
        diagnosticsDir.listFiles()?.forEach { it.delete() }
    }

    /**
     * Writes a real export through the production writer — wired exactly as `AppContainer` wires
     * it, i.e. rendering through the store's REDACTING `exportText`, so the tests below exercise
     * the shipped chain rather than a hand-rolled payload.
     */
    private fun writeExport(vararg messages: String): File {
        val store = DiagnosticsLogStore(EmptySource)
        val writer = DiagnosticsExportWriter(diagnosticsDir, renderPayload = store::exportText)
        val entries = (messages.takeIf { it.isNotEmpty() } ?: arrayOf("diagnostics payload"))
            .map {
                DiagnosticsLogEntry(
                    timeMillis = 1_700_000_000_000L,
                    level = DiagnosticsLevel.ERROR,
                    category = DiagnosticsCategory.SYNC.tag,
                    message = it,
                )
            }
        return runBlocking { writer.write(entries) }
    }

    private object EmptySource : DiagnosticsLogSource {
        override suspend fun recentEntries(sinceMillis: Long?, limit: Int) =
            SourceResult.Available(emptyList())
    }

    private fun stray(dir: File, name: String, content: String): File {
        dir.mkdirs()
        val file = File(dir, name)
        file.writeText(content)
        strays += file
        return file
    }

    // ------------------------------------------------------------------ provider scoping

    @Test fun diagnosticsProvider_grantsTheExportFile() {
        val export = writeExport()

        val uri = FileProvider.getUriForFile(context, DIAGNOSTICS_AUTHORITY, export)

        assertEquals(DIAGNOSTICS_AUTHORITY, uri.authority)
        assertEquals("content", uri.scheme)
        assertTrue("the granted URI names the export: $uri", uri.toString().endsWith(export.name))
    }

    /**
     * THE section-6.4 invariant, asserted rather than assumed: the BOOK provider must reject the
     * diagnostics export. If diagnostics had been shipped by adding a `diagnostics/` root to
     * `@xml/file_paths`, this call would succeed and this test would fail — which is exactly the
     * discrimination the positive test above cannot make.
     */
    @Test fun bookProvider_refusesTheDiagnosticsExport() {
        val export = writeExport()

        try {
            val leaked = FileProvider.getUriForFile(context, BOOK_AUTHORITY, export)
            fail(
                "the book provider must NOT be able to grant a diagnostics export — its scope is " +
                    "filesDir/books only (section 6.4). Got: $leaked",
            )
        } catch (expected: IllegalArgumentException) {
            // The book provider's <paths> has no root containing filesDir/diagnostics.
        }
    }

    /**
     * Positive control for the test above: the book provider still grants what it always granted,
     * so its refusal of the export is scoping, not breakage.
     */
    @Test fun bookProvider_stillGrantsFilesDirBooks() {
        val book = stray(booksDir, "wiring-probe-${UUID.randomUUID()}.epub", "not really an epub")

        val uri = FileProvider.getUriForFile(context, BOOK_AUTHORITY, book)

        assertEquals(BOOK_AUTHORITY, uri.authority)
        assertTrue(uri.toString().endsWith(book.name))
    }

    /** The mirror image: the diagnostics provider must not become a general filesDir grant. */
    @Test fun diagnosticsProvider_refusesFilesOutsideItsDirectory() {
        val book = stray(booksDir, "outside-probe-${UUID.randomUUID()}.epub", "book bytes")
        val loose = stray(context.filesDir, "outside-probe-${UUID.randomUUID()}.txt", "loose bytes")

        for (file in listOf(book, loose)) {
            try {
                val leaked = FileProvider.getUriForFile(context, DIAGNOSTICS_AUTHORITY, file)
                fail("the diagnostics provider must only grant filesDir/diagnostics. Got: $leaked for $file")
            } catch (expected: IllegalArgumentException) {
                // Correct — outside every configured root.
            }
        }
    }

    // ------------------------------------------------------------------ the share intent

    @Test fun shareDiagnosticsIntent_isAChooserWrappedSendWithGrantAndClipData() {
        val export = writeExport()

        val chooser = shareDiagnosticsIntent(context, export)
        assertNotNull("a valid export must produce a chooser intent", chooser)
        assertEquals(Intent.ACTION_CHOOSER, chooser!!.action)

        val send = chooser.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
        assertNotNull("the chooser wraps the ACTION_SEND intent", send)
        assertEquals(Intent.ACTION_SEND, send!!.action)
        assertEquals("text/plain", send.type)

        val uri = send.getParcelableExtra<android.net.Uri>(Intent.EXTRA_STREAM)
        assertNotNull("EXTRA_STREAM carries the content URI", uri)
        assertEquals(DIAGNOSTICS_AUTHORITY, uri!!.authority)

        assertTrue(
            "the read grant flag must be set, or the receiver cannot open the URI",
            send.flags and Intent.FLAG_GRANT_READ_URI_PERMISSION != 0,
        )

        val clip: ClipData? = send.clipData
        assertNotNull("a matching ClipData carries the grant on receivers that read the clip", clip)
        assertEquals(1, clip!!.itemCount)
        assertEquals("the ClipData URI matches EXTRA_STREAM", uri, clip.getItemAt(0).uri)
    }

    /**
     * Both probes are NAMED exactly like a real export, so the name check cannot be what rejects
     * them — the DIRECTORY guard is the assertion under test.
     */
    @Test fun shareDiagnosticsIntent_returnsNullForAFileOutsideTheDiagnosticsDirectory() {
        val book = stray(booksDir, "vreader-log-2026-08-05.txt", "book bytes wearing an export's name")
        val loose = stray(context.filesDir, "vreader-log-2026-08-04.txt", "loose bytes wearing an export's name")

        assertNull("a file under books/ is not a diagnostics export", shareDiagnosticsIntent(context, book))
        assertNull("a loose filesDir file is not a diagnostics export", shareDiagnosticsIntent(context, loose))
    }

    /**
     * Being IN the export directory is not enough — the file must also be NAMED like an export.
     * Without this, any file some other code dropped there could be granted to another app, which
     * is a wider door than "share the diagnostics export" needs.
     */
    @Test fun shareDiagnosticsIntent_returnsNullForAFileInTheDirectoryThatIsNotAnExport() {
        val notAnExport = stray(diagnosticsDir, "raw-${UUID.randomUUID()}.txt", "raw bytes nobody redacted")

        assertNull(shareDiagnosticsIntent(context, notAnExport))
        // Control: a real export in the same directory IS shareable, so this is the name, not the place.
        assertNotNull(shareDiagnosticsIntent(context, writeExport()))
    }

    /** The path-traversal shape specifically: a name that ESCAPES the directory it starts in. */
    @Test fun shareDiagnosticsIntent_returnsNullForATraversalPath() {
        // Named like an export, so only the canonical-directory guard can reject it.
        val loose = stray(context.filesDir, "vreader-log-2026-08-03.txt", "loose bytes")
        diagnosticsDir.mkdirs()   // the intermediate segment must exist for the path to resolve
        val traversal = File(diagnosticsDir, "../${loose.name}")

        assertTrue("precondition: the traversal path resolves to the loose file", traversal.exists())
        assertNull(
            "a path that only LOOKS like it is inside diagnostics/ must be rejected",
            shareDiagnosticsIntent(context, traversal),
        )
    }

    /**
     * A HARD LINK planted in the export directory is a second name for bytes that live elsewhere —
     * canonicalisation cannot see it (there is no target to resolve), so the directory check alone
     * would hand another app a book file through the diagnostics grant. Same-uid code could read
     * those bytes itself; what must not happen is OUR grant carrying them across the app boundary.
     *
     * Recorded observation rather than a silent skip: on this AVD (API 35) `Os.link` inside
     * app-private storage fails with **EACCES**, i.e. the platform refuses hard-link creation from
     * the untrusted-app domain, so the vector is not constructible here at all. That is a stronger
     * property than the guard provides — but it is the PLATFORM's property, not ours, and it varies
     * by kernel/SELinux configuration, so the `st_nlink` check stays as defence in depth and this
     * test activates wherever the vector does exist. The `Assume` failure surfaces as a SKIP in the
     * XML, so the platform verdict stays visible instead of being asserted away.
     */
    @Test fun shareDiagnosticsIntent_returnsNullForAHardLinkIntoAnotherDirectory() {
        val book = stray(booksDir, "hardlink-target-${UUID.randomUUID()}.epub", "book bytes")
        diagnosticsDir.mkdirs()
        val link = File(diagnosticsDir, "vreader-log-2026-08-05.txt")
        link.delete()
        try {
            Os.link(book.absolutePath, link.absolutePath)
        } catch (e: ErrnoException) {
            Assume.assumeNoException(
                "this build refuses hard-link creation from the app domain (errno ${e.errno}), so " +
                    "the vector the st_nlink guard covers cannot be constructed here",
                e,
            )
        }
        strays += link

        assertTrue("precondition: the link exists and reads the linked bytes", link.exists())
        assertEquals("book bytes", link.readText())
        assertNull(
            "a hard link is not an export, however plausible its name and location",
            shareDiagnosticsIntent(context, link),
        )
    }

    /**
     * A symlink INSIDE the export directory, pointing at a real export and NAMED like one, is still
     * not an export: it is a second name for the file, and `lstat` is what sees that.
     */
    @Test fun shareDiagnosticsIntent_returnsNullForASymlinkAlias() {
        val export = writeExport()
        val alias = File(diagnosticsDir, "vreader-log-2026-08-02.txt")
        alias.delete()
        Os.symlink(export.absolutePath, alias.absolutePath)
        strays += alias

        assertNull(shareDiagnosticsIntent(context, alias))
        assertNotNull("the real export is still shareable", shareDiagnosticsIntent(context, export))
    }

    @Test fun shareDiagnosticsIntent_returnsNullForAMissingFile() {
        val missing = File(diagnosticsDir, "vreader-log-1970-01-01.txt")
        missing.delete()

        assertNull(shareDiagnosticsIntent(context, missing))
    }

    // ------------------------------------------------------------------ the launcher

    /**
     * The no-receiver guarantee belongs to the LAUNCHER. Asserting it on the intent builder would be
     * vacuous — a function that only builds an Intent can never throw ActivityNotFoundException.
     */
    @Test fun shareDiagnostics_swallowsActivityNotFoundException() {
        val export = writeExport()
        var attempted = false
        val noReceiver = object : ContextWrapper(context) {
            override fun startActivity(intent: Intent) {
                attempted = true
                throw ActivityNotFoundException("no activity handles ACTION_SEND")
            }
        }

        shareDiagnostics(noReceiver, export)   // must not throw

        assertTrue(
            "the launcher must actually have attempted the start (otherwise this passes vacuously)",
            attempted,
        )
    }

    @Test fun shareDiagnostics_doesNotStartAnythingForAnOutOfScopeFile() {
        val loose = stray(context.filesDir, "launcher-probe-${UUID.randomUUID()}.txt", "loose bytes")
        var attempted = false
        val recording = object : ContextWrapper(context) {
            override fun startActivity(intent: Intent) { attempted = true }
        }

        shareDiagnostics(recording, loose)

        assertFalse("an out-of-scope file is a silent no-op, never a launch", attempted)
    }

    // ------------------------------------------------------------------ end-to-end payload

    /**
     * What a receiver would actually read. Going through `contentResolver.openInputStream` on the
     * granted URI proves the whole chain — store redaction, writer bytes, provider scope — rather
     * than any one link in isolation.
     */
    @Test fun grantedUri_streamsTheRedactedExport_withoutTheSeededSecret() {
        val secret = "connected-s3cret-${UUID.randomUUID()}"
        // The entry goes in RAW: redaction happens inside the writer's store renderer, which is how
        // production is wired. A test that pre-rendered the payload would prove only that one
        // correct call sequence is safe.
        val export = writeExport("backup failed password=$secret")

        val uri = FileProvider.getUriForFile(context, DIAGNOSTICS_AUTHORITY, export)
        val streamed = context.contentResolver.openInputStream(uri)!!.use {
            it.readBytes().toString(StandardCharsets.UTF_8)
        }

        assertFalse("the secret must not be readable through the granted URI", streamed.contains(secret))
        assertTrue(streamed.contains(DiagnosticsRedactor.PLACEHOLDER))
        assertEquals("the streamed bytes are exactly the promoted file", export.readText(), streamed)
    }
}
