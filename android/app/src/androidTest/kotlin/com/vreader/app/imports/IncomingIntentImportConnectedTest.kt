// Purpose: feature #155 WI-5 — ImportActivity's end-to-end body (resolve -> open -> enqueue ->
// hand off to MainActivity) asserted on a real device, where the platform (not a shadow) decides.
//
// Two tiers, deliberately:
//
//   * PRODUCTION TIER (no seam). A real third-party content URI — a MediaStore Downloads entry,
//     the only cross-app provider an instrumented test can populate without a picker — is opened
//     through an IMPLICIT VIEW intent, so the OS routes it and the app's REAL container
//     (IncomingBookResolver + IncomingImportCoordinator + BookImporter + Room) does the work. That
//     is the user's path: "Open with VReader" from a file manager. It also proves the two things
//     only production wiring can show — a genuine library row, and the persisted `sourceUri` cap.
//   * HOSTILE-PROVIDER TIER (the [ImportDependencies] seam). A provider that parks FOREVER, throws
//     from `query`, returns null, or hands back a document AFTER the caller gave up cannot be
//     expressed as a real ContentProvider from here: an androidTest source set cannot declare one
//     in the manifest, and `android.test.mock.MockContentResolver` needs a `useLibrary` this module
//     does not have. The seam substitutes the resolver boundary only; every ordering, ownership and
//     disposal decision under test is still ImportActivity's own.
//
// The load-bearing assertions (the ones that fail the WI if they go green for the wrong reason):
//
//   * D8 ADMISSION ORDER. `aStalledResolution…` samples the in-flight budget WHILE a provider is
//     parked and requires the WHOLE budget to be free. Acquiring the slot before resolution passes
//     every happy-path test and fails exactly this one — which is the point of writing it.
//   * DISPOSAL. `aResolveResultArrivingAfterTheBound…` asserts the stream is NOT closed early, then
//     that it IS closed once the abandoned call finally returns. Without the `dispose` hook that fd
//     has no owner at all.
//   * TOTALITY. `everyFailureClassInOneBatch…` feeds ONE URI of every failure class at once and
//     asserts outcomes == inputs, in input order. A single failure class would pass against an
//     enumerated `catch` list; the RuntimeException case is what makes the catch-all load-bearing.
//   * RULE 51. `importFailureMessage` is asserted to return the ALREADY-SHIPPED SAF-import copy and
//     to be SILENT for both new and duplicate imports — the undesigned feedback states are blocked
//     on needs-design #2030 and no new string may appear here.
//
// Fixtures are synthetic: the connected APK cannot read the gitignored `test-books/` tree, and
// every hostile case needs stream behaviour no real book can provide (a read that never returns, a
// provider that throws, a result that arrives after the deadline). WI-6 owns the real-book matrix.
package com.vreader.app.imports

import android.app.Activity
import android.content.ComponentName
import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.SystemClock
import android.provider.MediaStore
import androidx.annotation.RequiresApi
import androidx.room.Room
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.SdkSuppress
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import com.vreader.app.MainActivity
import com.vreader.app.VReaderApp
import com.vreader.app.data.BookImporter
import com.vreader.app.data.CollectionRepository
import com.vreader.app.data.ImportException
import com.vreader.app.data.LibraryRepository
import com.vreader.app.data.VReaderDatabase
import com.vreader.app.importFailureMessage
import com.vreader.app.library.LibraryEvent
import com.vreader.app.library.LibraryViewModel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExecutorCoroutineDispatcher
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import vreader.contracts.BookFormat
import java.io.ByteArrayInputStream
import java.io.File
import java.io.InputStream
import java.util.UUID
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger

@RunWith(AndroidJUnit4::class)
class IncomingIntentImportConnectedTest {

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private val context get() = instrumentation.targetContext

    // ── the test-owned coordinator (hostile-provider tier) ───────────────────────────────
    private lateinit var db: VReaderDatabase
    private lateinit var repository: LibraryRepository
    private lateinit var booksDir: File
    private lateinit var lane: ExecutorCoroutineDispatcher
    private lateinit var appScope: CoroutineScope
    private lateinit var coordinator: IncomingImportCoordinator
    private lateinit var outcomeJob: Job

    private val outcomes = CopyOnWriteArrayList<IncomingImportOutcome>()
    private val handoffs = CopyOnWriteArrayList<Intent>()
    private val handedOff = CountDownLatch(1)

    /** Every latch a fake provider parks on — released in [tearDown] so no thread leaks a test. */
    private val parkedLatches = CopyOnWriteArrayList<CountDownLatch>()

    /** MediaStore rows this test inserted, deleted in [tearDown]. */
    private val mediaStoreRows = CopyOnWriteArrayList<Uri>()

    @Before
    fun setUp() {
        db = Room.inMemoryDatabaseBuilder(context, VReaderDatabase::class.java).build()
        repository = LibraryRepository(db.bookDao(), db.readingPositionDao())
        booksDir = File(context.cacheDir, "wi5-books-${UUID.randomUUID()}").apply { mkdirs() }
        lane = Executors.newCachedThreadPool { runnable ->
            Thread(runnable, "wi5-lane").apply { isDaemon = true }
        }.asCoroutineDispatcher()
        appScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        coordinator = IncomingImportCoordinator(
            importer = BookImporter(booksDir, repository, lane),
            booksDir = booksDir,
            appScope = appScope,
            blockingLane = lane,
        )
        outcomeJob = appScope.launch { coordinator.outcomes.collect { outcomes += it } }
        finishAll<ImportActivity>()
        finishAll<MainActivity>()
    }

    @After
    fun tearDown() {
        ImportActivity.testDependencies = null
        parkedLatches.forEach { it.countDown() }
        outcomeJob.cancel()
        appScope.cancel()
        finishAll<ImportActivity>()
        finishAll<MainActivity>()
        mediaStoreRows.forEach { runCatching { context.contentResolver.delete(it, null, null) } }
        runBlocking {
            repository.listBooks().forEach { repository.deleteBook(it.fingerprintKey) }
        }
        db.close()
        booksDir.deleteRecursively()
        lane.close()
    }

    // ── PRODUCTION TIER — the user's real path ───────────────────────────────────────────

    /**
     * "Open with VReader" on a real third-party document: an IMPLICIT VIEW intent, resolved by the
     * OS, handled by the app's REAL container. Also covers the two cases only production wiring can
     * decide — the persisted `sourceUri` cap, and that re-sending the same bytes still yields ONE row.
     */
    @Test
    @SdkSuppress(minSdkVersion = Build.VERSION_CODES.Q)
    fun aRealContentUriImportsExactlyOneLibraryRowAndCapsTheSourceUri() {
        val container = (context.applicationContext as VReaderApp).container
        val before = runBlocking { container.repository.listBooks() }.map { it.fingerprintKey }.toSet()
        val name = "wi5-e2e-${UUID.randomUUID()}.epub"
        val row = insertDownload(name, bookBytes)
        // A deliberately over-long URI: the persisted provenance string must be capped at 2048,
        // and the cap must survive the whole activity -> coordinator -> importer hand-off.
        val padded = row.buildUpon().appendQueryParameter("pad", "p".repeat(3_000)).build()
        assertTrue("the padded URI must be longer than the cap", padded.toString().length > CAP)

        sendImplicitView(padded, "application/epub+zip")
        val imported = awaitNewBook(container.repository, before)
        assertEquals(BookFormat.epub, imported.originalFormat)
        assertEquals(CAP, imported.sourceUri!!.length)
        assertEquals(padded.toString().take(CAP), imported.sourceUri)

        // The SAME document again: content-addressed identity means one row, not two.
        finishAll<ImportActivity>()
        sendImplicitView(padded, "application/epub+zip")
        awaitNoImportActivity()
        val after = runBlocking { container.repository.listBooks() }
        assertEquals(
            "a duplicate import must not add a second row",
            1,
            after.count { it.fingerprintKey !in before },
        )

        runBlocking { container.repository.deleteBook(imported.fingerprintKey) }
        imported.localFilePath?.let { File(it).delete() }
    }

    /**
     * The confused-deputy guard (plan R13) plus the warm-start task model (D2) in one pass: a hostile
     * sender names OUR OWN FileProvider authority, and MainActivity is already on screen. Nothing is
     * imported, and afterwards there is still EXACTLY ONE MainActivity — `NEW_TASK | CLEAR_TOP |
     * SINGLE_TOP` reused the existing one instead of stacking a second over it.
     */
    @Test
    fun ourOwnFileProviderIsRejectedAndAWarmStartReusesTheOneMainActivity() {
        val container = (context.applicationContext as VReaderApp).container
        val before = runBlocking { container.repository.listBooks() }.size

        context.startActivity(
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        awaitTrue("MainActivity never started") { live<MainActivity>().isNotEmpty() }

        val ours = Uri.parse("content://${context.packageName}.fileprovider/books/stolen.epub")
        launchImport(Intent(Intent.ACTION_VIEW).setDataAndType(ours, "application/epub+zip"))
        awaitNoImportActivity()

        assertEquals(
            "our own FileProvider must never be imported from",
            before,
            runBlocking { container.repository.listBooks() }.size,
        )
        assertEquals("exactly one MainActivity after the hand-off", 1, live<MainActivity>().size)
    }

    /** A share that carried only EXTRA_TEXT: finish silently, and do NOT drag the user into VReader. */
    @Test
    fun aSendCarryingOnlyExtraTextFinishesWithoutLaunchingMainActivity() {
        finishAll<MainActivity>()
        awaitTrue("a stale MainActivity survived") { live<MainActivity>().isEmpty() }

        launchImport(Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, "hello"))
        awaitNoImportActivity()

        // Give a would-be hand-off time to land before declaring it absent.
        SystemClock.sleep(1_000)
        assertTrue("MainActivity must NOT be launched", live<MainActivity>().isEmpty())
        assertTrue("nothing may be enqueued", outcomes.isEmpty())
    }

    // ── D8 — the admission-order gap this WI closes ──────────────────────────────────────

    /**
     * THE D8 TEST. A provider whose cursor query never returns must not hold an in-flight slot while
     * it parks — so the WHOLE budget stays available to everyone else, and the activity still
     * finishes on the bound with exactly one outcome.
     *
     * Acquiring the slot before resolution passes every other test in this file and fails this one.
     */
    @Test
    fun aStalledResolutionNeverHoldsAnInFlightSlot() {
        val parked = park()
        val entered = CountDownLatch(1)
        installDeps(peek = { entered.countDown(); parked.await(); metadata })

        launchImport(view("content://hostile.stall/book.epub"))
        assertTrue("the fake provider was never called", entered.await(15, TimeUnit.SECONDS))

        // WHILE the provider is parked: every slot must still be free.
        val held = ArrayList<ImportSlot>()
        repeat(IncomingImportCoordinator.MAX_IN_FLIGHT) { index ->
            val slot = coordinator.acquireSlot()
            assertNotNull(
                "slot $index refused while a resolution was stalled — a slot was taken BEFORE " +
                    "resolution finished (D8's gap)",
                slot,
            )
            held += slot!!
        }
        held.forEach { it.release() }

        assertTrue("the activity never handed off", handedOff.await(30, TimeUnit.SECONDS))
        awaitOutcomes(1)
        assertEquals(IncomingImportOutcome.Failed, outcomes[0])
        awaitNoImportActivity()
        assertTrue("the budget must be free again", coordinator.acquireSlot() != null)
    }

    /**
     * A document produced AFTER the caller gave up owns an fd nobody else will ever close. The
     * `dispose` hook is the only owner — assert it is not closed early (which would be a different
     * bug: closing a stream still in flight), and that it IS closed once the late call returns.
     */
    @Test
    fun aResolveResultArrivingAfterTheBoundIsDisposed() {
        val stream = RecordingStream(bookBytes)
        val parked = park()
        installDeps(open = { uri -> parked.await(); pending(uri, "late.epub", stream) })

        launchImport(view("content://hostile.late/book.epub"))
        assertTrue("the activity never handed off", handedOff.await(30, TimeUnit.SECONDS))
        awaitOutcomes(1)
        assertEquals(IncomingImportOutcome.Failed, outcomes[0])
        assertFalse("the stream must not be closed before the call returns", stream.closed.get())

        parked.countDown()   // the provider finally answers — for a caller that is long gone
        awaitTrue("the late PendingImport's fd was never disposed") { stream.closed.get() }
    }

    // ── the total invariant: EXACTLY one outcome per input URI ───────────────────────────

    /**
     * ONE URI of every failure class in a single batch. The count is the assertion: a branch that
     * `continue`s, returns, or lets a throwable escape the loop shows up here as a missing outcome,
     * and an enumerated `catch` list shows up as the whole batch aborting at the RuntimeException.
     */
    @Test
    fun everyFailureClassInOneBatchYieldsOneOutcomePerUriInOrder() {
        val parked = park()
        val opens = AtomicInteger(0)
        installDeps(
            peek = { uri ->
                when (uri.host) {
                    "throws" -> throw SecurityException("no read permission")
                    "stall" -> { parked.await(); metadata }
                    "huge" -> IncomingMetadata("huge.epub", IncomingImportCoordinator.MAX_IMPORT_BYTES + 1)
                    else -> metadata
                }
            },
            open = { uri ->
                opens.incrementAndGet()
                when (uri.host) {
                    "refuses" -> null
                    "unsupported" -> throw ImportException.UnsupportedFormat("notes.docx")
                    "hostile" -> throw RuntimeException("provider blew up")
                    else -> pending(uri, "good.epub", RecordingStream(bookBytes))
                }
            },
        )

        val uris = arrayListOf(
            Uri.parse("content://${context.packageName}.fileprovider/books/ours.epub"),
            Uri.parse("content://throws/a.epub"),
            Uri.parse("content://stall/b.epub"),
            Uri.parse("content://refuses/c.epub"),
            Uri.parse("content://unsupported/notes.docx"),
            Uri.parse("content://hostile/d.epub"),
            Uri.parse("content://huge/e.epub"),
            Uri.parse("content://good/f.epub"),
        )
        launchImport(
            Intent(Intent.ACTION_SEND_MULTIPLE)
                .setType("application/epub+zip")
                .putParcelableArrayListExtra(Intent.EXTRA_STREAM, uris),
        )

        assertTrue("the activity never handed off", handedOff.await(60, TimeUnit.SECONDS))
        awaitOutcomes(uris.size)
        assertEquals(
            listOf(
                IncomingImportOutcome.Unreadable,                       // our own FileProvider
                IncomingImportOutcome.Unreadable,                       // query threw
                IncomingImportOutcome.Failed,                           // query parked past the bound
                IncomingImportOutcome.Unreadable,                       // provider refused to open
                IncomingImportOutcome.Unsupported("notes.docx"),        // no known format
                IncomingImportOutcome.Unreadable,                       // RuntimeException — the catch-all
                IncomingImportOutcome.TooLarge,                         // declared oversize, never opened
            ),
            outcomes.take(uris.size - 1),
        )
        assertTrue("the last URI must import", outcomes[uris.size - 1] is IncomingImportOutcome.Imported)

        // Nothing was opened for the rejected-before-open classes (guard / query failure / oversize).
        assertEquals("only the four openable URIs may reach the open call", 4, opens.get())
        // PERMIT BALANCE: the whole budget is back, so a 21st import still admits.
        val held = (0 until IncomingImportCoordinator.MAX_IN_FLIGHT).map {
            requireNotNull(coordinator.acquireSlot()) { "slot $it leaked by the mixed batch" }
        }
        held.forEach { it.release() }
        assertEquals("one hand-off per intent, not per URI", 1, handoffs.size)
    }

    /** A declared oversize is rejected by the PRE-OPEN preflight — no descriptor is ever created. */
    @Test
    fun aDeclaredOversizeIsRejectedBeforeAnythingIsOpened() {
        val opens = AtomicInteger(0)
        installDeps(
            peek = { IncomingMetadata("huge.epub", IncomingImportCoordinator.MAX_IMPORT_BYTES + 1) },
            open = { uri -> opens.incrementAndGet(); pending(uri, "huge.epub", RecordingStream(bookBytes)) },
        )

        launchImport(view("content://huge/book.epub"))
        assertTrue(handedOff.await(30, TimeUnit.SECONDS))
        awaitOutcomes(1)
        assertEquals(IncomingImportOutcome.TooLarge, outcomes[0])
        assertEquals("nothing may be opened after a declared-oversize rejection", 0, opens.get())
    }

    // ── ownership across the activity's death, and the hand-off itself ───────────────────

    /**
     * The grant-revocation path (plan R3): the copy runs on the coordinator's appScope over an
     * ALREADY-OPEN fd, so it completes even though ImportActivity is long gone. The gate makes the
     * ordering deterministic — the import cannot finish before the activity does.
     */
    @Test
    fun anImportCompletesAfterImportActivityIsDestroyed() {
        val gate = park()
        installDeps(open = { uri -> pending(uri, "slow.epub", GatedStream(bookBytes, gate)) })

        launchImport(view("content://good/slow.epub"))
        assertTrue(handedOff.await(30, TimeUnit.SECONDS))
        awaitNoImportActivity()
        assertTrue("the import must still be in flight while the activity is gone", outcomes.isEmpty())

        gate.countDown()
        awaitOutcomes(1)
        assertTrue(outcomes[0] is IncomingImportOutcome.Imported)
        assertEquals(1, runBlocking { repository.listBooks() }.size)
    }

    /**
     * D2: an externally-started activity runs in the SENDER's task, so `CLEAR_TOP | SINGLE_TOP`
     * without `NEW_TASK` would target the wrong task and stack a second MainActivity.
     */
    @Test
    fun theHandoffIntentTargetsMainActivityInItsOwnTask() {
        installDeps()
        launchImport(view("content://good/book.epub"))
        assertTrue(handedOff.await(30, TimeUnit.SECONDS))

        val intent = handoffs.single()
        assertEquals(MainActivity::class.java.name, intent.component?.className)
        assertTrue("FLAG_ACTIVITY_NEW_TASK", intent.flags and Intent.FLAG_ACTIVITY_NEW_TASK != 0)
        assertTrue("FLAG_ACTIVITY_CLEAR_TOP", intent.flags and Intent.FLAG_ACTIVITY_CLEAR_TOP != 0)
        assertTrue("FLAG_ACTIVITY_SINGLE_TOP", intent.flags and Intent.FLAG_ACTIVITY_SINGLE_TOP != 0)
    }

    /**
     * PERMIT LEAK across a mid-loop cancellation: one URI has already been opened and admitted when
     * the activity is destroyed while the next one's provider is parked. Nothing may survive that —
     * not the descriptor, not the slot — and the batch is abandoned wholesale, which is the exact
     * scope of the one-outcome-per-URI invariant.
     */
    @Test
    fun aCancelledBatchLeaksNoSlotAndNoDescriptor() {
        val opened = RecordingStream(bookBytes)
        val parked = park()
        val entered = CountDownLatch(1)
        installDeps(
            peek = { uri ->
                if (uri.host == "stall") {
                    entered.countDown()
                    parked.await()
                }
                metadata
            },
            open = { uri -> pending(uri, "good.epub", opened) },
        )

        launchImport(
            Intent(Intent.ACTION_SEND_MULTIPLE)
                .setType("application/epub+zip")
                .putParcelableArrayListExtra(
                    Intent.EXTRA_STREAM,
                    arrayListOf(Uri.parse("content://good/a.epub"), Uri.parse("content://stall/b.epub")),
                ),
        )
        assertTrue("the second URI never reached the provider", entered.await(30, TimeUnit.SECONDS))

        finishAll<ImportActivity>()      // destroyed mid-loop, with URI 1 already opened + admitted
        awaitNoImportActivity()

        awaitTrue("the already-opened descriptor was never closed") { opened.closed.get() }
        val held = (0 until IncomingImportCoordinator.MAX_IN_FLIGHT).map {
            requireNotNull(coordinator.acquireSlot()) { "slot $it leaked by the cancelled batch" }
        }
        held.forEach { it.release() }
        assertTrue("a cancelled batch enqueues nothing", outcomes.isEmpty())
        assertTrue("a cancelled batch never hands off", handoffs.isEmpty())
    }

    // ── RULE 51 — the shipped toast copy, and silence everywhere else ────────────────────

    /**
     * The inbound feedback states (in-progress / added / already-in-library / unsupported) are
     * UNDESIGNED and blocked on needs-design #2030. Failures therefore reuse the SAF-import copy
     * shipped in LibraryViewModel.import VERBATIM, and success — new OR duplicate — is SILENT.
     *
     * The expectations are DERIVED, not retyped: the shipped ViewModel is driven through two real
     * failures and the strings it emits are what `importFailureMessage` must return. Asserting the
     * same literals twice would pass however far the two copies drifted apart.
     */
    @Test
    @SdkSuppress(minSdkVersion = Build.VERSION_CODES.Q)
    fun failureOutcomesReuseTheShippedToastCopyAndSuccessIsSilent() {
        val viewModel = LibraryViewModel(
            repository = repository,
            importer = BookImporter(booksDir, repository, lane),
            collectionRepository = CollectionRepository(db.collectionDao()),
            resolver = context.contentResolver,
        )
        val emitted = CopyOnWriteArrayList<String>()
        val collector = appScope.launch {
            viewModel.events.collect { if (it is LibraryEvent.ImportFailed) emitted += it.message }
        }

        // (1) a document no provider will hand over — the SHIPPED generic failure copy.
        viewModel.import(Uri.parse("content://com.example.absent/missing.epub"))
        awaitTrue("the shipped ViewModel emitted no generic failure") { emitted.size >= 1 }
        val generic = emitted[0]

        // (2) a REAL, openable document whose extension names no known format — the SHIPPED
        // unsupported copy, carrying the provider's own display name.
        val row = insertDownload("wi5-copy-${UUID.randomUUID()}.docx", bookBytes, "application/octet-stream")
        val storedName = displayNameOf(row)
        viewModel.import(row)
        awaitTrue("the shipped ViewModel emitted no unsupported failure") { emitted.size >= 2 }
        val unsupported = emitted[1]
        collector.cancel()

        assertEquals(generic, importFailureMessage(IncomingImportOutcome.Failed))
        assertEquals(generic, importFailureMessage(IncomingImportOutcome.TooLarge))
        assertEquals(unsupported, importFailureMessage(IncomingImportOutcome.Unsupported(storedName)))
        // The one string with no reachable SAF trigger (`openInputStream` returning null rather
        // than throwing) is pinned literally against LibraryViewModel.import's own branch.
        assertEquals("Couldn't open the file", importFailureMessage(IncomingImportOutcome.Unreadable))
        assertNull(
            "a new import is silent",
            importFailureMessage(IncomingImportOutcome.Imported("k", BookFormat.epub, false)),
        )
        assertNull(
            "a duplicate is silent too",
            importFailureMessage(IncomingImportOutcome.Imported("k", BookFormat.epub, true)),
        )
    }

    // ── helpers ──────────────────────────────────────────────────────────────────────────

    private val metadata get() = IncomingMetadata("book.epub", 32L)

    private val bookBytes = ByteArray(4_096) { (it % 251).toByte() }

    /** A latch a fake provider parks on; released in [tearDown] so no lane thread outlives the test. */
    private fun park(): CountDownLatch = CountDownLatch(1).also { parkedLatches += it }

    private fun pending(
        uri: Uri,
        name: String,
        stream: InputStream,
        size: Long? = 32L,
        format: BookFormat = BookFormat.epub,
    ) = PendingImport(
        uri = uri,
        displayName = name,
        format = format,
        sourceUri = uri.toString().take(CAP),
        declaredSize = size,
        stream = stream,
    )

    /** Substitutes the resolver boundary (and captures the hand-off instead of starting MainActivity). */
    private fun installDeps(
        peek: suspend (Uri) -> IncomingMetadata = { metadata },
        open: suspend (Uri) -> PendingImport? = { uri -> pending(uri, "book.epub", RecordingStream(bookBytes)) },
        resolveTimeoutMillis: Long = RESOLVE_MS,
    ) {
        ImportActivity.testDependencies = {
            ImportDependencies(
                coordinator = coordinator,
                peek = peek,
                open = open,
                freeSpaceDir = context.filesDir,
                handoff = { intent -> handoffs += intent; handedOff.countDown() },
                resolveTimeoutMillis = resolveTimeoutMillis,
            )
        }
    }

    private fun view(uri: String) =
        Intent(Intent.ACTION_VIEW).setDataAndType(Uri.parse(uri), "application/epub+zip")

    /** Explicit component: the OS routing matrix is WI-2's test; this file tests the body. */
    private fun launchImport(intent: Intent) {
        intent.component = ComponentName(context, ImportActivity::class.java)
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    /** The user's path: no component, so the platform's own filters decide. */
    private fun sendImplicitView(uri: Uri, mime: String) {
        context.startActivity(
            Intent(Intent.ACTION_VIEW)
                .setDataAndType(uri, mime)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION),
        )
    }

    @RequiresApi(Build.VERSION_CODES.Q)
    private fun insertDownload(
        name: String,
        bytes: ByteArray,
        mime: String = "application/epub+zip",
    ): Uri {
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = requireNotNull(resolver.insert(collection, values)) { "MediaStore refused the insert" }
        mediaStoreRows += uri
        requireNotNull(resolver.openOutputStream(uri)) { "MediaStore refused the write" }
            .use { it.write(bytes) }
        values.clear()
        values.put(MediaStore.MediaColumns.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return uri
    }

    /** The name the provider ACTUALLY stored — MediaStore may adjust the one it was handed. */
    private fun displayNameOf(uri: Uri): String {
        val projection = arrayOf(MediaStore.MediaColumns.DISPLAY_NAME)
        context.contentResolver.query(uri, projection, null, null, null)!!.use { cursor ->
            assertTrue("the inserted row disappeared", cursor.moveToFirst())
            return cursor.getString(0)
        }
    }

    private fun awaitNewBook(repo: LibraryRepository, before: Set<String>): com.vreader.app.data.Book {
        val deadline = SystemClock.uptimeMillis() + AWAIT_MS
        while (SystemClock.uptimeMillis() < deadline) {
            val fresh = runBlocking { repo.listBooks() }.firstOrNull { it.fingerprintKey !in before }
            if (fresh != null) return fresh
            SystemClock.sleep(POLL_MS)
        }
        throw AssertionError("no new library row appeared within ${AWAIT_MS}ms")
    }

    private fun awaitOutcomes(expected: Int) {
        awaitTrue("expected $expected outcomes, saw $outcomes") { outcomes.size >= expected }
        assertEquals("exactly one outcome per input URI", expected, outcomes.size)
    }

    private fun awaitTrue(message: String, condition: () -> Boolean) {
        val deadline = SystemClock.uptimeMillis() + AWAIT_MS
        while (SystemClock.uptimeMillis() < deadline) {
            if (condition()) return
            SystemClock.sleep(POLL_MS)
        }
        throw AssertionError(message)
    }

    private fun awaitNoImportActivity() =
        awaitTrue("ImportActivity never finished") { live<ImportActivity>().isEmpty() }

    /** Every activity of [T] that is not yet DESTROYED — a STOPPED one is still on the stack. */
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
        val deadline = SystemClock.uptimeMillis() + AWAIT_MS
        while (SystemClock.uptimeMillis() < deadline && live<T>().isNotEmpty()) SystemClock.sleep(POLL_MS)
    }

    /** Records `close()` — the only way to see whether an abandoned document's fd found an owner. */
    private class RecordingStream(bytes: ByteArray) : ByteArrayInputStream(bytes) {
        val closed = AtomicBoolean(false)

        override fun close() {
            closed.set(true)
            super.close()
        }
    }

    /** Delivers nothing until [gate] opens, so "the activity died first" is deterministic, not a race. */
    private class GatedStream(private val bytes: ByteArray, private val gate: CountDownLatch) :
        InputStream() {

        private var index = 0

        override fun read(): Int {
            gate.await()
            return if (index < bytes.size) bytes[index++].toInt() and 0xFF else -1
        }

        override fun read(b: ByteArray, off: Int, len: Int): Int {
            gate.await()
            if (index >= bytes.size) return -1
            val n = minOf(len, bytes.size - index)
            System.arraycopy(bytes, index, b, off, n)
            index += n
            return n
        }
    }

    private companion object {
        const val CAP = IncomingBookResolver.MAX_SOURCE_URI_CHARS
        const val AWAIT_MS = 30_000L
        const val POLL_MS = 50L

        /** Short enough to keep the suite quick, long enough to survive a loaded emulator. */
        const val RESOLVE_MS = 4_000L
    }
}
