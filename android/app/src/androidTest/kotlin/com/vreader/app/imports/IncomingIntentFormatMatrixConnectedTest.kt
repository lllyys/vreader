// Purpose: feature #155 WI-6 — the Gate-5 acceptance matrix. Every format VReader claims to
// accept from another app is imported HERE, on a device, through the production graph, from a
// REAL third-party content provider, over an intent the PLATFORM routed.
//
// There is no [ImportDependencies] seam anywhere in this file. WI-5's connected class owns the
// hostile-provider tier (a provider that parks forever, throws, or answers after the deadline);
// this one owns the opposite question — does a real book, of every real format, actually land in
// the library when a file manager says "Open with VReader".
//
// WHAT MAKES A GREEN HERE MEAN SOMETHING:
//
//   * REAL BOOKS, AND THE FALLBACK IS FAILURE (AGENTS.md "real books first"). EPUB / TXT / AZW3
//     come from `test-books/books/`, pushed to the app's external files dir, and every accessor is
//     `require`-d on EXISTENCE AND EXACT BYTE COUNT. A run without the push FAILS LOUDLY with the
//     adb command in the message; it never degrades to a synthetic stand-in. That is the whole
//     point: a matrix that silently substitutes reports five formats green while having exercised
//     two. The connected task wipes `/sdcard/Android/data/com.vreader.app/`, so the fixtures must
//     be re-pushed BEFORE EVERY RUN:
//
//     ```
//     adb -s emulator-5554 shell mkdir -p /sdcard/Android/data/com.vreader.app/files
//     adb -s emulator-5554 push "test-books/books/epub/The Half Second - Li Xiaolai.epub" \
//         /sdcard/Android/data/com.vreader.app/files/wi6-real.epub
//     adb -s emulator-5554 push "test-books/books/epub/道诡异仙 - 狐尾的笔.epub" \
//         /sdcard/Android/data/com.vreader.app/files/wi6-real-large.epub
//     adb -s emulator-5554 push test-books/books/txt/黑暗血时代.txt \
//         /sdcard/Android/data/com.vreader.app/files/wi6-real.txt
//     adb -s emulator-5554 push "test-books/books/azw3/Bei Tao Yan De Yong Qi - Zi Wo.azw3" \
//         /sdcard/Android/data/com.vreader.app/files/wi6-real.azw3
//     adb -s emulator-5554 push docs/architecture.md \
//         /sdcard/Android/data/com.vreader.app/files/wi6-real.md
//     ```
//
//   * IDENTITY, NOT JUST SHAPE (Gate-4 round 1, High). Every import is bound to the SOURCE BYTES:
//     the test hashes the fixture itself with its own `MessageDigest`, composes the canonical key
//     the contract mandates, then waits for THAT EXACT KEY and asserts the row's sha, byte count,
//     provenance URI and the STORED ARTIFACT'S OWN DIGEST against it. Byte COUNT alone would pass
//     for any same-sized payload, and "a new row appeared" would pass for a row some earlier
//     intent produced — both were real holes in the first draft of this file.
//
//   * THE TWO FORMATS WITH NO REAL BOOK, NAMED AS SUCH. `test-books/books/` holds `azw3/`,
//     `epub/` and `txt/` only. PDF therefore uses the committed `sample-3page.pdf` androidTest
//     asset — a structurally real PDF, synthetic in content — under the explicit AGENTS.md
//     exception "the format has no real book (no real PDF or MD today)". MD goes one better than
//     that exception allows: `docs/architecture.md` is a real, large, deeply structured Markdown
//     document from this repo (it is simply not a *book*), so it is pushed like the real books —
//     with the weaker identity check a LIVING file permits, stated exactly at [RealFixture.MD].
//
//   * THE MANIFEST FILTERS DO THE ROUTING, NOT A ComponentName LITERAL. Every intent here is
//     started PACKAGE-SCOPED (`setPackage`) and never component-pinned, so the platform still
//     runs its filter matcher and a filter that stopped matching would throw
//     ActivityNotFoundException instead of silently passing. A bare implicit start — what a file
//     manager fires BEFORE the user picks — is not used, because the system interposes the "Open
//     with" chooser whenever another app handles the type and a test cannot detect that in
//     advance: package visibility (Android 11+) means this app sees only ITSELF in
//     `queryIntentActivities`. See [packageScoped]; the chooser leg of the user's path is driven
//     by hand for the evidence file (rule 47's production-reachability clause), and the routing
//     table is owned by `ImportFilterResolutionConnectedTest`.
//
//   * MALFORMED INPUT IS ASSERTED AS IT BEHAVES, NOT AS ONE MIGHT WISH. A zero-byte file, a
//     truncated EPUB and a PDF named `.txt` all IMPORT, because the import layer is deliberately
//     content-agnostic: format comes from the extension (D3 steps 1-2 beat sniffing so a book's
//     identity cannot change under it), identity comes from the bytes, and validation belongs to
//     the reader that later opens the book. These tests pin that contract — and that the exported
//     entry point survives all three — rather than pretending a rejection happens.
//
// Fixtures are staged into MediaStore Downloads, the only cross-app provider an instrumented test
// can populate without a picker; the resulting `content://media/...` URI is read through the same
// ContentResolver path a file manager's document would be.
//
// Run ONE class per connected invocation, and never drive the emulator while it is in flight.
package com.vreader.app.imports

import android.app.Activity
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.provider.MediaStore
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.SdkSuppress
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import com.vreader.app.MainActivity
import com.vreader.app.VReaderApp
import com.vreader.app.data.Book
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import vreader.contracts.BookFormat
import vreader.contracts.Identity
import java.io.File
import java.io.OutputStream
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList

@RunWith(AndroidJUnit4::class)
@SdkSuppress(minSdkVersion = Build.VERSION_CODES.Q)   // MediaStore.Downloads staging
class IncomingIntentFormatMatrixConnectedTest {

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()

    /** The app under test — the REAL production graph, never a test-owned copy. */
    private val context get() = instrumentation.targetContext
    private val container get() = (context.applicationContext as VReaderApp).container
    private val resolver get() = context.contentResolver
    private val packageManager get() = context.packageManager

    /**
     * Keys THIS test caused to exist — registered at staging time, and only ever after
     * [registerKey] has established that no row already carried them. Canonical identities are
     * deterministic (an empty `.epub` hashes the same in every run, and a fixture may legitimately
     * be in the library already), so "the key I expected" is NOT by itself proof of ownership
     * (Gate-4 round 2, Medium).
     */
    private val ownedKeys = CopyOnWriteArrayList<String>()

    private val stagedUris = CopyOnWriteArrayList<Uri>()
    private val tempFiles = CopyOnWriteArrayList<File>()

    @Before
    fun setUp() {
        finishAll<ImportActivity>()
        finishAll<MainActivity>()
    }

    /**
     * Removes ONLY what this test brought into existence: a row under a key that was absent when
     * this test registered it, or a row whose provenance is one of its own staged URIs (which
     * catches a row created under an UNEXPECTED key — a wrongly-resolved format — that would
     * otherwise leak), never one whose key predates the test.
     *
     * Every step is isolated and every failure accumulated, because an exception in the first
     * deletion must not abandon the MediaStore rows and temp files behind it; the bookkeeping is
     * cleared in a `finally` so one failing test cannot poison the next one's attribution.
     */
    @After
    fun tearDown() {
        val leaked = ArrayList<String>()
        try {
            // Individually wrapped: a window-manager hiccup finishing an activity must not abandon
            // the row / MediaStore / temp-file cleanup behind it (Gate-4 round 3, Medium).
            runCatching { finishAll<ImportActivity>() }.onFailure { leaked += "finish ImportActivity: $it" }
            runCatching { finishAll<MainActivity>() }.onFailure { leaked += "finish MainActivity: $it" }
            val ourUris = stagedUris.map { it.toString() }.toSet()
            val ours = { book: Book ->
                book.fingerprintKey in ownedKeys || book.sourceUri in ourUris
            }
            runCatching {
                runBlocking {
                    container.repository.listBooks().filter(ours).forEach { book ->
                        runCatching {
                            book.localFilePath?.let { path ->
                                val artifact = File(path)
                                if (artifact.exists() && !artifact.delete()) leaked += "artifact $path"
                            }
                            container.repository.deleteBook(book.fingerprintKey)
                        }.onFailure { leaked += "row ${book.fingerprintKey}: $it" }
                    }
                    container.repository.listBooks().filter(ours)
                        .forEach { leaked += "row ${it.fingerprintKey} survived deletion" }
                }
            }.onFailure { leaked += "library cleanup: $it" }

            stagedUris.forEach { uri ->
                // 0 rows deleted is a FAILURE, not a success: the document is still there.
                val deleted = runCatching { resolver.delete(uri, null, null) }
                    .onFailure { leaked += "MediaStore row $uri: $it" }
                    .getOrDefault(0)
                if (deleted <= 0) leaked += "MediaStore row $uri (delete affected $deleted rows)"
            }
            tempFiles.forEach { file ->
                runCatching { if (file.exists() && !file.delete()) leaked += "temp file ${file.path}" }
                    .onFailure { leaked += "temp file ${file.path}: $it" }
            }
        } finally {
            ownedKeys.clear()
            stagedUris.clear()
            tempFiles.clear()
        }
        // Reported, never swallowed: a leak here silently poisons the NEXT test's attribution.
        if (leaked.isNotEmpty()) throw AssertionError("teardown could not release: $leaked")
    }

    /**
     * Registers [key] as this test's to clean up, and REFUSES to run against a library that
     * already contains it.
     *
     * Canonical identities are deterministic, so a pre-existing row under the same key is not
     * this test's to delete — but leaving it alone is not enough either: the import under test
     * REWRITES that row's import-owned columns (provenance included), so teardown would leave a
     * stranger's row mutated and pointing at a URI it is about to delete. Refusing here, BEFORE
     * anything is dispatched, is the only resolution confined to this file (Gate-4 round 3,
     * Medium). It fires only on a dirty device; the connected task installs a fresh app.
     */
    private fun registerKey(key: String) {
        val existing = runBlocking { container.repository.findBook(key) }
        if (existing != null) {
            throw AssertionError(
                "the library already contains '$key' (title '${existing.title}') before this test " +
                    "staged it, so the import under test would mutate a row this test does not own. " +
                    "Clear the app's data and re-run: adb shell pm clear com.vreader.app",
            )
        }
        ownedKeys += key
    }

    // ── the five formats, each through a system-routed VIEW ──────────────────────────────

    /** REAL EPUB (1.3 MB, `The Half Second - Li Xiaolai.epub`). */
    @Test
    fun epubRealBookImportsThroughOpenWith() {
        assertImports(RealFixture.EPUB, BookFormat.epub, "application/epub+zip")
    }

    /**
     * REAL TXT — the 14 MB CJK novel `黑暗血时代.txt`, staged under a CJK display name so the
     * whole chain (provider name -> NFC sanitize -> title) is exercised on non-ASCII text, and
     * so "14 MB+" is covered by a genuine book rather than a generated blob.
     */
    @Test
    fun txtRealCjkBookImportsThroughOpenWith() {
        val book = assertImports(RealFixture.TXT, BookFormat.txt, "text/plain", name = cjkName())
        assertTrue(
            "the CJK title must survive the provider -> sanitize -> import chain, was '${book.title}'",
            book.title.contains("黑暗血时代"),
        )
    }

    /** REAL AZW3 (6.3 MB Kindle book). */
    @Test
    fun azw3RealBookImportsThroughOpenWith() {
        assertImports(RealFixture.AZW3, BookFormat.azw3, "application/vnd.amazon.ebook")
    }

    /**
     * PDF — the committed `sample-3page.pdf` androidTest asset, under the AGENTS.md exception
     * "the format has no real book": `test-books/books/` contains azw3/, epub/ and txt/ only, so
     * no real PDF book exists in this repo to prefer over it.
     */
    @Test
    fun pdfImportsThroughOpenWith() {
        val pdf = assetFile(PDF_ASSET)
        val staged = stage(pdf, "wi6-${UUID.randomUUID()}.pdf", "application/pdf", BookFormat.pdf)
        assertImported(openWith(staged, "application/pdf", BookFormat.pdf), staged, BookFormat.pdf)
    }

    /**
     * MD — the repo's own `docs/architecture.md` (deeply nested headings). There is no real
     * Markdown *book* in `test-books/books/`, which is the AGENTS.md exception; a real repo
     * document is nonetheless strictly better evidence than a hand-written fixture.
     *
     * The identity guarantee is the WEAKER one a living file permits, and [RealFixture.MD] states
     * its scope exactly: size floor, title line and section anchors REJECT an absent push and a
     * hand-written stub, but do not bind the pushed bytes to the worktree's copy; the import
     * assertions then bind the import to whatever was pushed. Cryptographic binding would need the
     * harness to pass the digest in at push time — a runner change outside this file.
     */
    @Test
    fun mdRealRepoDocumentImportsThroughOpenWith() {
        assertImports(RealFixture.MD, BookFormat.md, "text/markdown")
    }

    // ── size, duplicate identity, and the malformed matrix ───────────────────────────────

    /**
     * A REAL 19 MB book (`道诡异仙 - 狐尾的笔.epub`) — well past the plan's 14 MB bar and past
     * anything a `read()` loop bug would survive. [assertImported] compares the STORED ARTIFACT'S
     * SHA-256 with the source's, so this is byte-for-byte over 19 MB, not merely equal length.
     */
    @Test
    fun aNineteenMegabyteRealBookImportsWithoutTruncation() {
        val source = RealFixture.EPUB_LARGE.require()
        assertTrue("the large fixture must exceed 14 MB", source.length() > 14L * 1024 * 1024)
        assertImports(RealFixture.EPUB_LARGE, BookFormat.epub, "application/epub+zip")
    }

    /**
     * THE CROSS-ENTRY-POINT IDENTITY CASE (plan §8.5). The same bytes imported through the SAF
     * path and then through "Open with" must be ONE book: same canonical key, no second row, no
     * second artifact — only the provenance URI is rewritten to the new source. This is what the
     * whole extension-beats-magic-bytes rule (D3) exists to protect, and it is the one property
     * the per-format tests above cannot show, because each of them starts from an empty library.
     */
    @Test
    fun aBookAlreadyImportedThroughTheSafPathIsNotDuplicatedByAnOpenWith() {
        val source = RealFixture.EPUB.require()
        val sha = sha256(source)
        val key = Identity.canonicalKey(BookFormat.epub.name, sha, source.length())
        registerKey(key)

        // The SAF path: the app's own importer, the one LibraryViewModel.import drives.
        val safUri = "content://com.example.saf/document/wi6-${UUID.randomUUID()}"
        val first = runBlocking {
            container.importer.importStream(safUri, "wi6-saf.epub", source.inputStream())
        }
        assertEquals("the SAF import must mint the contract's canonical key", key, first.fingerprintKey)
        val artifact = File(requireNotNull(first.localFilePath) { "the SAF import stored no artifact" })
        val booksDir = requireNotNull(artifact.parentFile) { "the artifact has no directory" }
        val rowsAfterSaf = runBlocking { container.repository.listBooks() }.size
        val artifactsAfterSaf = requireNotNull(booksDir.list()) { "unreadable books dir" }.size

        // Now the SAME bytes, arriving from a file manager. Staged with a NULL format because this
        // key is already registered above: re-registering it would trip [registerKey]'s
        // pre-existing-row guard on the row this very test just created.
        val staged = stage(source, "wi6-${UUID.randomUUID()}.epub", "application/epub+zip", null)
        context.startActivity(routedOpenWith(staged.uri, "application/epub+zip"))
        // The upsert rewrites the import-owned columns, so the row's provenance flipping to the
        // inbound URI is the completion signal — no sleep, and it cannot be satisfied by the
        // pre-existing row.
        awaitTrue("the inbound import never reached the existing row") {
            runBlocking { container.repository.findBook(key) }?.sourceUri == staged.uri.toString()
        }

        val after = runBlocking { container.repository.listBooks() }
        assertEquals("re-importing the same bytes must not add a row", rowsAfterSaf, after.size)
        assertEquals("exactly one row may carry the key", 1, after.count { it.fingerprintKey == key })
        assertEquals(
            "re-importing the same bytes must not add an artifact",
            artifactsAfterSaf,
            requireNotNull(booksDir.list()) { "unreadable books dir" }.size,
        )
        assertEquals("the stored bytes must be unchanged", sha, sha256(artifact))
    }

    /**
     * A ZERO-BYTE document. It IMPORTS, as a zero-byte row: the import layer resolves format from
     * the extension and identity from the bytes, and never inspects content. Pinned because the
     * load-bearing property of an EXPORTED entry point here is that an empty payload produces one
     * ordinary outcome instead of a crash, a hang, or a half-written artifact — not because an
     * empty "book" is desirable. (Rejecting it would be a product decision about what the library
     * may contain, outside this WI's write-set.)
     */
    @Test
    fun aZeroByteDocumentImportsAsAZeroByteRowRatherThanCrashingTheEntryPoint() {
        val empty = bytesFile("wi6-empty", ByteArray(0))
        val staged = stage(empty, "wi6-${UUID.randomUUID()}.epub", "application/epub+zip", BookFormat.epub)
        val book = assertImported(openWith(staged, "application/epub+zip", BookFormat.epub), staged, BookFormat.epub)
        assertEquals("a zero-byte payload must be stored as zero bytes", 0L, book.fileByteCount)
    }

    /**
     * A TRUNCATED EPUB — the real book's first 4 KB, which is a valid OCF header and nothing
     * else. It imports as an EPUB with its OWN identity: the extension decides the format
     * (D3 steps 1-2) and the truncated bytes hash to a different key than the whole book, so it
     * can never collide with, or overwrite, the intact import.
     */
    @Test
    fun aTruncatedEpubImportsUnderItsOwnIdentity() {
        val whole = RealFixture.EPUB.require()
        val head = whole.inputStream().use { input ->
            val buffer = ByteArray(4096)
            var filled = 0
            while (filled < buffer.size) {
                val read = input.read(buffer, filled, buffer.size - filled)
                if (read <= 0) break
                filled += read
            }
            require(filled == buffer.size) { "the real EPUB is unexpectedly shorter than 4 KB" }
            buffer
        }
        val staged = stage(
            bytesFile("wi6-truncated", head),
            "wi6-${UUID.randomUUID()}.epub",
            "application/epub+zip",
            BookFormat.epub,
        )
        val book = assertImported(openWith(staged, "application/epub+zip", BookFormat.epub), staged, BookFormat.epub)
        assertTrue(
            "the truncated prefix must NOT share the whole book's identity",
            book.fingerprintKey != Identity.canonicalKey(
                BookFormat.epub.name, sha256(whole), whole.length(),
            ),
        )
    }

    /**
     * A LYING EXTENSION: PDF bytes named `.txt`. It imports as TXT — deliberately. Sniffing only
     * ever FILLS A GAP the name and MIME left (plan D3 / §13.3): if magic bytes could override a
     * declared extension, the same file imported from SAF and from an intent could mint two
     * different canonical keys and two library rows. Identity stability beats being clever.
     *
     * The digest assertions make this precise: the row must carry the PDF's OWN sha under a `txt:`
     * key — i.e. the real PDF bytes were imported, and the extension alone decided the format.
     */
    @Test
    fun aPdfNamedTxtImportsAsTxtBecauseTheExtensionBeatsTheMagicBytes() {
        val pdf = assetFile(PDF_ASSET)
        val magic = ByteArray(5)
        pdf.inputStream().use { it.read(magic) }
        assertEquals(
            "the fixture must really start with the PDF magic the sniffer would have matched",
            "%PDF-",
            String(magic, Charsets.US_ASCII),
        )
        val staged = stage(pdf, "wi6-${UUID.randomUUID()}.txt", "text/plain", BookFormat.txt)
        assertImported(openWith(staged, "text/plain", BookFormat.txt), staged, BookFormat.txt)
    }

    // ── SEND and SEND_MULTIPLE ───────────────────────────────────────────────────────────

    /** A share of one real book: `SEND` carries its payload in EXTRA_STREAM, not in the data URI. */
    @Test
    fun aSendOfOneRealBookImportsIt() {
        val source = RealFixture.EPUB.require()
        val staged = stage(source, "wi6-${UUID.randomUUID()}.epub", "application/epub+zip", BookFormat.epub)
        context.startActivity(
            packageScoped(
                Intent(Intent.ACTION_SEND)
                    .setType("application/epub+zip")
                    .putExtra(Intent.EXTRA_STREAM, staged.uri),
            ),
        )
        assertImported(awaitBook(staged, BookFormat.epub), staged, BookFormat.epub)
    }

    /**
     * A PARTIAL BATCH: two real books with one unclassifiable payload BETWEEN them (bytes that are
     * not valid UTF-8, so even the sniffer's text branch declines). The supported items must
     * import; the unsupported one must not abort the batch and must leave no row.
     *
     * The negative half needs no settling delay, and deliberately so: the coordinator drains ONE
     * queue with ONE worker in input order, so the third item's row EXISTING proves the second
     * item has already been processed. A `sleep`-then-assert-absent would be a guess about a
     * loaded emulator; this is an ordering argument (Gate-4 round 1, Medium).
     */
    @Test
    fun aSendMultiplePartialBatchImportsTheSupportedItemsAndSkipsTheUnsupportedOne() {
        val epub = stage(
            RealFixture.EPUB.require(), "wi6-${UUID.randomUUID()}.epub",
            "application/epub+zip", BookFormat.epub,
        )
        // 0xC0 is an invalid UTF-8 lead byte, so this decodes as nothing and carries no PDF / OCF /
        // MOBI magic: the one payload the whole D3 chain must refuse.
        val gibberishFile = bytesFile("wi6-gibberish", ByteArray(2048) { 0xC0.toByte() })
        val gibberish = stage(
            gibberishFile, "wi6-${UUID.randomUUID()}.docx", "application/octet-stream", null,
        )
        val azw3 = stage(
            RealFixture.AZW3.require(), "wi6-${UUID.randomUUID()}.azw3",
            "application/vnd.amazon.ebook", BookFormat.azw3,
        )

        context.startActivity(
            packageScoped(
                Intent(Intent.ACTION_SEND_MULTIPLE)
                    .setType("application/octet-stream")
                    .putParcelableArrayListExtra(
                        Intent.EXTRA_STREAM,
                        arrayListOf(epub.uri, gibberish.uri, azw3.uri),
                    ),
            ),
        )

        // The LAST item first: its arrival is what licenses the negative assertion below.
        assertImported(awaitBook(azw3, BookFormat.azw3), azw3, BookFormat.azw3)
        assertImported(awaitBook(epub, BookFormat.epub), epub, BookFormat.epub)
        val rows = runBlocking { container.repository.listBooks() }
        assertTrue(
            "the unclassifiable payload must not have produced a row, saw ${rows.map { it.title }}",
            rows.none { it.contentSHA256 == gibberish.sha || it.sourceUri == gibberish.uri.toString() },
        )
    }

    // ── the shared assertions ────────────────────────────────────────────────────────────

    /** Stages [fixture], opens it the way a file manager would, and asserts the imported row. */
    private fun assertImports(
        fixture: RealFixture,
        format: BookFormat,
        mime: String,
        name: String = "wi6-${UUID.randomUUID()}.${fixture.extension}",
    ): Book {
        val staged = stage(fixture.require(), name, mime, format)
        return assertImported(openWith(staged, mime, format), staged, format)
    }

    /**
     * Everything an accepted inbound document must be true of at once: it is THE staged bytes (the
     * row's sha, and the stored artifact's own digest, both equal the digest this test computed
     * from the fixture), under the canonical key the cross-platform contract composes, with the
     * resolved format, and with provenance naming THE EXACT URI this test staged — so no row
     * produced by any other intent can satisfy it.
     */
    private fun assertImported(book: Book, staged: Staged, format: BookFormat): Book {
        assertEquals("resolved format", format, book.originalFormat)
        assertEquals("canonical key", staged.keyFor(format), book.fingerprintKey)
        assertEquals("content digest", staged.sha, book.contentSHA256)
        assertEquals("hashed byte count", staged.bytes, book.fileByteCount)
        assertEquals("provenance must name the exact staged document", staged.uri.toString(), book.sourceUri)
        val artifact = File(requireNotNull(book.localFilePath) { "no local artifact was stored" })
        assertTrue("the artifact must exist at ${artifact.path}", artifact.isFile)
        assertEquals("the STORED artifact must be byte-for-byte the source", staged.sha, sha256(artifact))
        return book
    }

    // ── routing ──────────────────────────────────────────────────────────────────────────

    /** What a file manager's "Open with" fires once VReader is picked, scoped to this package. */
    private fun routedOpenWith(uri: Uri, mime: String): Intent =
        packageScoped(Intent(Intent.ACTION_VIEW).setDataAndType(uri, mime))

    private fun openWith(staged: Staged, mime: String, format: BookFormat): Book {
        context.startActivity(routedOpenWith(staged.uri, mime))
        return awaitBook(staged, format)
    }

    /**
     * Hands [intent] to the platform SCOPED TO OUR PACKAGE — no ComponentName, so the routing is
     * still done by ImportActivity's manifest FILTERS: a filter that stopped matching would make
     * this `startActivity` throw ActivityNotFoundException rather than quietly pass.
     *
     * Why not a bare implicit start, which is what a file manager fires BEFORE the user picks?
     * Because the system would interpose the "Open with" CHOOSER whenever another app also handles
     * the type, and a test cannot see that coming: since Android 11, `queryIntentActivities` is
     * filtered by PACKAGE VISIBILITY, so this app sees only ITSELF and would report "sole handler"
     * for types the platform actually offers to Chrome (`text/plain`) and Drive
     * (`application/pdf`) as well. That is not hypothetical — the first run of this class started
     * implicitly, the system resolver came up (`ResolverListAdapter: Add DisplayResolveInfo …
     * ImportActivity`), and the run parked until the timeout. `setPackage` removes the other
     * candidates while leaving the filter match load-bearing.
     *
     * So this is the POST-CHOOSER equivalent, and the chooser leg itself — a human tapping VReader
     * among those candidates — is NOT claimed by this class. It is discharged in the WI's evidence
     * file by driving the real DocumentsUI chooser, and the routing table by
     * `ImportFilterResolutionConnectedTest` against the same PackageManager.
     */
    private fun packageScoped(intent: Intent): Intent {
        intent.setPackage(context.packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
        val ours = packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
        assertEquals(
            "the platform must route ${intent.action} + ${intent.type} to ImportActivity, and to " +
                "nothing else of ours (a filter on MainActivity would stack one over an open reader)",
            listOf(IMPORT_ACTIVITY),
            ours.map { it.activityInfo.name },
        )
        Log.i(TAG, "${intent.action} + ${intent.type} -> filter-matched ${ours.single().activityInfo.name}")
        return intent
    }

    // ── fixtures ─────────────────────────────────────────────────────────────────────────

    /**
     * A real document pushed to the app's external files dir. [require] is the ONLY accessor and
     * it never falls back: a missing or wrong-sized fixture fails the test with the adb command
     * that fixes it, because an acceptance matrix that quietly substitutes a stand-in proves
     * nothing about the format it names.
     */
    private enum class RealFixture(
        val fileName: String,
        val extension: String,
        val source: String,
        /** The immutable book fixtures are pinned to the byte — nothing else is that file. */
        val exactBytes: Long? = null,
        /** For a LIVING repo document, whose size legitimately drifts: a floor plus content anchors. */
        val minBytes: Long = 0,
        val firstLine: String? = null,
        val mustContain: List<String> = emptyList(),
    ) {
        EPUB("wi6-real.epub", "epub", "test-books/books/epub/The Half Second - Li Xiaolai.epub", 1_302_140),
        EPUB_LARGE("wi6-real-large.epub", "epub", "test-books/books/epub/道诡异仙 - 狐尾的笔.epub", 19_381_838),
        TXT("wi6-real.txt", "txt", "test-books/books/txt/黑暗血时代.txt", 14_059_220),
        AZW3("wi6-real.azw3", "azw3", "test-books/books/azw3/Bei Tao Yan De Yong Qi - Zi Wo.azw3", 6_288_371),

        /**
         * Not a book — the repo's own architecture doc; see the class KDoc's MD note.
         *
         * SCOPE OF THIS CHECK, stated exactly (Gate-4 round 2, Medium — the earlier "a substituted
         * document cannot pass both" was FALSE): `docs/architecture.md` is a LIVING file, so its
         * identity cannot be a pinned digest without breaking this test on every unrelated docs
         * commit. The size floor, the title line and the section anchors below IDENTIFY the push
         * — they make an absent push and a hand-written stub fail loudly, which is the substitution
         * this fixture policy exists to stop — but they do NOT cryptographically bind the bytes to
         * the worktree's copy. What the import assertions then bind is the IMPORT to whatever was
         * pushed, byte for byte. Cryptographic binding would need the harness to hand the digest to
         * the test at push time; that is a runner change outside this file's write-set.
         */
        MD(
            "wi6-real.md", "md", "docs/architecture.md",
            minBytes = 50_000,
            firstLine = "# VReader Architecture",
            mustContain = listOf("## System Diagram", "## Layers", "## File Organization"),
        );

        fun require(): File {
            val dir = requireNotNull(
                InstrumentationRegistry.getInstrumentation().targetContext.getExternalFilesDir(null),
            ) { "no external files dir on this device" }
            val file = File(dir, fileName)
            require(file.isFile && file.canRead()) { pushHint("it is absent") }
            exactBytes?.let { expected ->
                require(file.length() == expected) {
                    pushHint("it is ${file.length()} bytes, not the real document's $expected")
                }
            }
            require(file.length() >= minBytes) {
                pushHint("it is ${file.length()} bytes, below the ${minBytes}-byte floor")
            }
            firstLine?.let { expected ->
                val head = file.bufferedReader().use { it.readLine() }
                require(head == expected) { pushHint("its first line is '$head', not '$expected'") }
            }
            if (mustContain.isNotEmpty()) {
                val text = file.readText()
                mustContain.forEach { anchor ->
                    require(text.contains(anchor)) { pushHint("it does not contain '$anchor'") }
                }
            }
            return file
        }

        private fun pushHint(problem: String) =
            "WI-6 requires the REAL document at getExternalFilesDir(null)/$fileName — $problem. " +
                "The connected task wipes /sdcard/Android/data/com.vreader.app/, so re-push it: " +
                "adb -s emulator-5554 push \"$source\" " +
                "/sdcard/Android/data/com.vreader.app/files/$fileName"
    }

    /**
     * A committed androidTest asset, materialised in the app's cache. REWRITTEN on every call: a
     * cache file left by an earlier run (or by anything else) must never stand in for the asset
     * the test names (Gate-4 round 1, Medium).
     */
    private fun assetFile(asset: String): File {
        val file = File(context.cacheDir, "wi6-asset-$asset")
        instrumentation.context.assets.open(asset).use { input ->
            file.outputStream().use(input::copyTo)
        }
        tempFiles += file
        return file
    }

    private fun bytesFile(prefix: String, bytes: ByteArray): File =
        File(context.cacheDir, "$prefix-${UUID.randomUUID()}").apply { writeBytes(bytes) }
            .also { tempFiles += it }

    /** The real CJK book's own name, kept CJK, made unique so MediaStore never de-duplicates it. */
    private fun cjkName() = "黑暗血时代-${UUID.randomUUID()}.txt"

    // ── MediaStore staging (a REAL third-party provider) ─────────────────────────────────

    /** A staged document plus the identity the app MUST derive from it if it really imports it. */
    private data class Staged(val uri: Uri, val sha: String, val bytes: Long) {
        fun keyFor(format: BookFormat): String = Identity.canonicalKey(format.name, sha, bytes)
    }

    /**
     * Copies [source] into MediaStore Downloads and returns its expected identity, computed HERE
     * from the file's own bytes with this test's own digest — so the assertions compare two
     * independent paths to the same number rather than restating the importer's output.
     *
     * [format] is the format the app is expected to resolve; it is registered for teardown so a
     * failed test still cleans up. Pass null when the document is expected NOT to import.
     */
    private fun stage(source: File, name: String, mime: String, format: BookFormat?): Staged {
        val sha = sha256(source)
        val uri = insertDownload(name, mime) { out ->
            source.inputStream().use { it.copyTo(out, COPY_CHUNK) }
        }
        val staged = Staged(uri, sha, source.length())
        format?.let { registerKey(staged.keyFor(it)) }
        return staged
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun insertDownload(name: String, mime: String, write: (OutputStream) -> Unit): Uri {
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = requireNotNull(resolver.insert(collection, values)) { "MediaStore refused to insert $name" }
        stagedUris += uri
        requireNotNull(resolver.openOutputStream(uri)) { "MediaStore refused to write $name" }.use(write)
        values.clear()
        values.put(MediaStore.MediaColumns.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        // MediaStore may adjust a display name to match the MIME type, and the resolution chain
        // reads the STORED name — so a silent rename is logged here rather than surfacing later as
        // a puzzling format mismatch.
        Log.i(TAG, "staged '$name' as '${storedNameOf(uri)}' ($mime) at $uri")
        return uri
    }

    private fun storedNameOf(uri: Uri): String {
        val projection = arrayOf(MediaStore.MediaColumns.DISPLAY_NAME)
        resolver.query(uri, projection, null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) return cursor.getString(0)
        }
        return "<unknown>"
    }

    // ── waiting, hashing, and the activity stack ─────────────────────────────────────────

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(COPY_CHUNK)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    /**
     * Waits for the row THIS staged document must produce — the exact canonical key for [format]
     * AND provenance naming this exact URI, never "some new row" (Gate-4 round 1, High) and never
     * merely "these bytes under any format" (round 2, Low: identical bytes already present under
     * another format would have returned that row and failed the assertions while the real import
     * was still queued).
     *
     * On timeout the diagnostic reports what the bytes DID become, so a wrongly-resolved format
     * reads as a format mismatch rather than a bare timeout.
     */
    private fun awaitBook(staged: Staged, format: BookFormat): Book {
        val key = staged.keyFor(format)
        val uri = staged.uri.toString()
        val deadline = SystemClock.uptimeMillis() + AWAIT_MS
        while (SystemClock.uptimeMillis() < deadline) {
            runBlocking { container.repository.findBook(key) }
                ?.takeIf { it.sourceUri == uri }
                ?.let { return it }
            SystemClock.sleep(POLL_MS)
        }
        val sameBytes = runBlocking { container.repository.listBooks() }
            .filter { it.contentSHA256 == staged.sha || it.sourceUri == uri }
        throw AssertionError(
            "no $format row for the staged document appeared within ${AWAIT_MS}ms " +
                "(expected key $key). Rows carrying those bytes or that URI: " +
                sameBytes.map { "${it.fingerprintKey} (${it.originalFormat}) from ${it.sourceUri}" },
        )
    }

    private fun awaitTrue(message: String, condition: () -> Boolean) {
        val deadline = SystemClock.uptimeMillis() + AWAIT_MS
        while (SystemClock.uptimeMillis() < deadline) {
            if (condition()) return
            SystemClock.sleep(POLL_MS)
        }
        throw AssertionError(message)
    }

    private inline fun <reified T : Activity> live(): List<T> {
        var found: List<T> = emptyList()
        instrumentation.runOnMainSync {
            val monitor = ActivityLifecycleMonitorRegistry.getInstance()
            found = Stage.values()
                .filter { it != Stage.DESTROYED }
                .flatMap { monitor.getActivitiesInStage(it) }
                .filterIsInstance<T>()
                .distinct()
        }
        return found
    }

    private inline fun <reified T : Activity> finishAll() {
        val living = live<T>()
        if (living.isEmpty()) return
        instrumentation.runOnMainSync { living.forEach { it.finish() } }
        val deadline = SystemClock.uptimeMillis() + SETTLE_MS
        while (SystemClock.uptimeMillis() < deadline && live<T>().isNotEmpty()) SystemClock.sleep(POLL_MS)
    }

    private companion object {
        const val TAG = "WI155-MATRIX"
        const val IMPORT_ACTIVITY = "com.vreader.app.imports.ImportActivity"
        const val PDF_ASSET = "sample-3page.pdf"

        const val COPY_CHUNK = 64 * 1024

        /** Generous: the largest fixture is 19 MB, hashed and copied on a loaded emulator. */
        const val AWAIT_MS = 120_000L
        const val SETTLE_MS = 15_000L
        const val POLL_MS = 100L
    }
}
