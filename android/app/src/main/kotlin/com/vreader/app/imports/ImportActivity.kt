// Purpose: feature #155 — the app's single exported inbound-document entry point.
// "Open with VReader" / "Share to VReader" resolve HERE, not to MainActivity: every
// activity is launchMode `standard`, so a VIEW filter on MainActivity would stack a
// second MainActivity over an open reader (plan D2).
//
// Task model: the activity is declared `taskAffinity=""` + `noHistory` +
// `excludeFromRecents`, and is themed TRANSLUCENT (never `Theme.NoDisplay` — a
// no-display activity must finish before it would become visible, but this one must
// stay alive long enough to open the incoming streams while its read grant is still
// valid; plan D6). Nothing is ever drawn.
//
// Pipeline (WI-5): urisFrom(intent) → per URI { self-targeting guard → BOUNDED peek →
// pre-open size/free-space preflight → BOUNDED resolveAndOpen → in-flight slot } → enqueue
// on the process-wide coordinator → hand off to MainActivity → finish().
//
// Key decisions (each stated where it is enforced; `admit` and `admitOne` carry the detail):
//   * EXACTLY ONE IncomingItem PER URI — `admit` for the precise scope, `itemFor` for the
//     catch-all that makes it hold against an attacker-controlled provider.
//   * THE SLOT IS TAKEN LAST, so a stalled provider can never hold one — `admitOne`, with the
//     open-descriptor worst case that costs and the follow-up that would make it strict.
//   * A try/catch DOES NOT BOUND A PROVIDER. `query` / `openInputStream` are synchronous and
//     uninterruptible, so both resolver calls run through the coordinator's BoundedCallGate,
//     with the `dispose` hook that owns a document arriving after we walked away.
//   * STREAMS ARE OPENED WHILE THIS ACTIVITY IS ALIVE. A FLAG_GRANT_READ_URI_PERMISSION grant
//     dies when it finishes; an already-open fd survives. Bare URIs never reach the coordinator.
//
// @coordinates-with: AndroidManifest.xml (the four intent filters — MIME matching and
//   pathPattern matching live in SEPARATE filters because <data> elements merge into a
//   cross-product within one filter), res/values/themes.xml (Theme.VReader.Import),
//   IncomingBookResolver (peek / resolveAndOpen), IncomingImportCoordinator (slots, queue,
//   outcomes), MainActivity (collects those outcomes and shows the shipped failure toast)
package com.vreader.app.imports

import android.content.ContentResolver
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.net.Uri
import android.os.Bundle
import android.os.Parcelable
import androidx.activity.ComponentActivity
import androidx.annotation.VisibleForTesting
import androidx.core.content.IntentCompat
import androidx.lifecycle.lifecycleScope
import com.vreader.app.MainActivity
import com.vreader.app.VReaderApp
import com.vreader.app.data.ImportException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.InputStream
import kotlin.coroutines.cancellation.CancellationException

/**
 * ImportActivity's collaborators in ONE place.
 *
 * The resolver is held as two function references rather than an [IncomingBookResolver] so a
 * connected test can stand in a provider that parks forever, throws from `query`, or answers
 * after the deadline — behaviour a real `ContentProvider` cannot express from an androidTest
 * source set (it cannot declare one in the manifest). Everything under test — the admission
 * order, the bounds, the ownership transfer, the hand-off — is still this activity's own.
 */
class ImportDependencies(
    val coordinator: IncomingImportCoordinator,
    val peek: suspend (Uri) -> IncomingMetadata,
    val open: suspend (Uri) -> PendingImport?,
    /** Whose free space the pre-open preflight consults (app-private storage). */
    val freeSpaceDir: File,
    val handoff: (Intent) -> Unit,
    val resolveTimeoutMillis: Long = IncomingImportCoordinator.RESOLVE_TIMEOUT.inWholeMilliseconds,
)

class ImportActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val uris = urisFrom(intent)
        if (uris.isEmpty()) {
            // A share carrying only EXTRA_TEXT (a plain-text snippet), or any other payload with
            // no URI in it: there is nothing to import, so finish WITHOUT launching MainActivity —
            // the user returns to the sending app instead of being dropped into our Library.
            finish()
            return
        }
        val deps = dependencies()
        lifecycleScope.launch {
            try {
                // The loop's only blocking work is our OWN filesystem's free-space check; every
                // untrusted provider call is relocated (and bounded) by the coordinator's gate.
                withContext(Dispatchers.IO) { admit(uris, deps) }
                deps.handoff(handoffIntent())
            } finally {
                // In a `finally` because a hand-off that throws (an activity-not-found, a wedged
                // window manager) must not leave this invisible, translucent activity on the stack.
                finish()
            }
        }
    }

    /** The production graph, or — in a DEBUGGABLE build only — the connected test's substitute. */
    private fun dependencies(): ImportDependencies {
        val override = testDependencies
        if (override != null && applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            return override(this)
        }
        val container = (application as VReaderApp).container
        val resolver = container.incomingBookResolver
        return ImportDependencies(
            coordinator = container.incomingImportCoordinator,
            peek = resolver::peek,
            open = resolver::resolveAndOpen,
            // filesDir, NOT the books directory: `usableSpace` is 0 for a path that does not
            // exist yet (nothing has been imported), which would reject every first import.
            // Both live on the same volume, so the number is the same one that matters.
            freeSpaceDir = filesDir,
            handoff = { startActivity(it) },
        )
    }

    /**
     * Builds EXACTLY ONE [IncomingItem] per URI and hands them over, IN INPUT ORDER.
     *
     * `transferred` counts the items the coordinator has actually accepted, so ownership is tracked
     * per item rather than per batch: every item beyond that count — after a throw, or after this
     * scope is cancelled mid-loop because the activity is being destroyed — has its stream closed
     * and its slot returned. Items are offered ONE AT A TIME for exactly that reason: `enqueue` is
     * documented never to throw, but a hostile stream's `close()` can still push a process-fatal
     * error out of its rejection path, and a single batch call would leave us unable to tell which
     * items had already changed hands (double-releasing is harmless — a slot release is idempotent
     * — but double-closing a stream the coordinator now owns is not ours to do).
     *
     * SCOPE OF THE INVARIANT, precisely. Cancellation (the activity being destroyed) is cooperative,
     * so it can only be observed at a suspension point, and there are exactly two windows:
     *
     *  * DURING CONSTRUCTION — the batch is abandoned wholesale: nothing is enqueued, every opened
     *    stream is closed and every slot returned, and NO outcome is emitted. That is the plan's
     *    chosen trade for a mid-loop cancellation (the alternative, importing documents for a user
     *    who has already navigated away, is not what it picked), and
     *    `aCancelledBatchLeaksNoSlotAndNoDescriptor` pins it.
     *  * AFTER CONSTRUCTION — the transfer loop below contains no suspension point, so once it is
     *    entered it always runs to completion: every item reaches the coordinator and every outcome
     *    is still emitted. Only the hand-off is skipped, and the coordinator buffers those outcomes
     *    until MainActivity is next opened.
     *
     * So one outcome per URI holds for every batch except one cancelled mid-construction.
     */
    private suspend fun admit(uris: List<Uri>, deps: ImportDependencies) {
        val items = ArrayList<IncomingItem>(uris.size)
        var transferred = 0
        try {
            for (uri in uris) items += itemFor(uri, deps)
            while (transferred < items.size) {
                deps.coordinator.enqueue(listOf(items[transferred]))   // never suspends
                transferred++
            }
        } finally {
            releaseAll(items.subList(transferred, items.size))
        }
    }

    /**
     * Releases every item the coordinator never received.
     *
     * Per item, isolated: [closeQuietly] deliberately rethrows a process-fatal error, and letting
     * that abort the loop would strand every later item's slot. The first one is remembered and
     * rethrown once the rest have been released.
     */
    private fun releaseAll(items: List<IncomingItem>) {
        var fatal: Throwable? = null
        for (item in items) {
            try {
                release(item)
            } catch (e: Throwable) {
                if (fatal == null) fatal = e
            }
        }
        fatal?.let { throw it }
    }

    /** An item the coordinator never received: close its descriptor, give its slot back. */
    private fun release(item: IncomingItem) {
        if (item !is IncomingItem.Ready) return
        try {
            closeQuietly(item.pending.stream)
        } finally {
            item.slot.release()                 // idempotent — a double release is harmless
        }
    }

    /**
     * The TOTAL wrapper: whatever an attacker-controlled provider does, this URI still produces one
     * item. Only two things escape — our own cancellation (the activity is going away, and the
     * caller's `finally` releases the batch) and a genuinely process-fatal error.
     */
    private suspend fun itemFor(uri: Uri, deps: ImportDependencies): IncomingItem = try {
        admitOne(uri, deps)
    } catch (e: CancellationException) {
        // Structured cancellation is honored — but ONLY when it is ours. A provider that merely
        // THREW this type while we are still active is just another hostile throwable, and must
        // not cost the rest of the batch its outcomes.
        if (!currentCoroutineContext().isActive) throw e
        unreadable()
    } catch (e: Throwable) {
        if (e.isFatal()) throw e
        unreadable()                            // CATCH-ALL, not an enumerated list of types
    }

    private suspend fun admitOne(uri: Uri, deps: ImportDependencies): IncomingItem {
        // CONFUSED-DEPUTY GUARD (plan R13): a hostile sender can point us at OUR OWN private
        // storage and have us copy it into the library on its say-so. Rejected BEFORE anything
        // else — and it still emits an item, because a silently dropped URI breaks
        // one-outcome-per-URI.
        if (isSelfTargeted(uri)) return unreadable()

        val gate = deps.coordinator.boundedCalls
        // ADMISSION FOR THE RESOLVER CALL ITSELF. Taking the import slot last (below) means a
        // stalled URI never reaches `acquireSlot`, which is the only other place the abandoned-call
        // threshold is consulted — so without this check a hostile batch of parking providers would
        // face no ceiling at all. Each abandoned call costs a parked thread (and possibly an fd)
        // until the provider returns, and the count self-heals when it does.
        if (gate.abandonedCalls >= IncomingImportCoordinator.MAX_ABANDONED_CALLS) return failed()

        val metadata = when (val call = gate.call(deps.resolveTimeoutMillis, PEEK) { deps.peek(uri) }) {
            is BoundedCall.Completed -> call.value
            is BoundedCall.Failed -> return unreadable()
            BoundedCall.TimedOut -> return failed()
        }

        // PRE-OPEN preflight (plan D8): "reject before opening" only means anything here, where
        // no descriptor exists yet — a cursor's declared size is all we get for free.
        val declared = metadata.declaredSize
        if (declared != null) {
            if (declared > IncomingImportCoordinator.MAX_IMPORT_BYTES) {
                return IncomingItem.PreResolved(IncomingImportOutcome.TooLarge)
            }
            if (deps.freeSpaceDir.usableSpace <= declared + FREE_SPACE_HEADROOM_BYTES) return failed()
        }

        // Re-checked here, not just before `peek`: a concurrent activity may have exhausted the
        // budget while this one was inside its cursor query.
        if (gate.abandonedCalls >= IncomingImportCoordinator.MAX_ABANDONED_CALLS) return failed()

        val opened = gate.call<PendingImport?>(
            timeoutMillis = deps.resolveTimeoutMillis,
            name = RESOLVE,
            // MANDATORY: a document produced after we walked away owns an fd with no other owner.
            dispose = { it?.stream?.close() },
        ) { deps.open(uri) }
        val pending = when (opened) {
            is BoundedCall.Completed -> opened.value ?: return unreadable()
            is BoundedCall.Failed -> return failureItem(opened.error)
            BoundedCall.TimedOut -> return failed()
        }

        // ADMISSION LAST (plan D8's gap): only a document that actually RESOLVED takes one of the
        // MAX_IN_FLIGHT slots, so a provider stalled in resolution can never hold one.
        //
        // What that costs, stated honestly: the slot no longer precedes the open, so it does not by
        // itself cap open descriptors. Per activity the window is ONE (this loop is sequential and
        // the stream is closed immediately if admission is refused); across N concurrently-launched
        // ImportActivity instances it is N transient descriptors, plus whatever sits inside calls
        // this app has already walked away from — which is what the abandoned-call check above
        // bounds. Making that ceiling strict belongs to BoundedCallGate, which admits a call's job
        // before consulting any budget (Gate-4 round 1, CRITICAL — reported as a follow-up against
        // IncomingImportCoordinator, outside this WI's write-set).
        val slot = deps.coordinator.acquireSlot() ?: run {
            closeQuietly(pending.stream)
            return failed()
        }
        // The slot exists only in a local until the item carrying it is returned; an allocation
        // failure in between would otherwise strand it where the caller's cleanup cannot see it.
        var carried = false
        try {
            val ready = IncomingItem.Ready(pending, slot)
            carried = true
            return ready
        } finally {
            if (!carried) {
                closeQuietly(pending.stream)
                slot.release()
            }
        }
    }

    /**
     * The resolver's failure, mapped TOTALLY: an unsupported format anywhere in the (bounded)
     * cause chain names the file, and anything else at all is [IncomingImportOutcome.Unreadable].
     */
    private fun failureItem(error: Throwable): IncomingItem {
        val unsupported = generateSequence(error) { it.cause }
            .take(MAX_CAUSE_DEPTH)
            .filterIsInstance<ImportException.UnsupportedFormat>()
            .firstOrNull()
            ?: return unreadable()
        return IncomingItem.PreResolved(IncomingImportOutcome.Unsupported(unsupported.name))
    }

    /**
     * Would honouring [uri] make us read OUR OWN storage on a stranger's say-so?
     *
     * Two shapes, because the manifest routes two schemes. A `content://` URI can name one of our
     * own FileProviders. A `file://` URI is the sharper one: it carries no authority at all, and
     * `ContentResolver.openInputStream` on it opens the path with THIS process's uid — so a sender
     * that suppresses its own StrictMode can hand us `file:///data/data/<us>/databases/…` and have
     * the result land in the library as a "book". Anything else is refused outright: the only
     * schemes this entry point can read are the two the manifest advertises.
     */
    private fun isSelfTargeted(uri: Uri): Boolean = when (uri.scheme?.lowercase()) {
        ContentResolver.SCHEME_CONTENT -> uri.authority.isNullOrEmpty() || isOwnAuthority(uri.authority)
        ContentResolver.SCHEME_FILE -> isAppPrivatePath(uri.path)
        else -> true
    }

    /**
     * Is [authority] served by one of OUR OWN providers?
     *
     * The literal application-ID prefix is checked FIRST so the guard cannot fail OPEN: every
     * authority this app declares is `<applicationId>.<name>` (books, diagnostics exports), and a
     * PackageManager lookup that throws or returns null would otherwise wave those through. The
     * lookup then runs as defence in depth, for an authority of ours that ever stops following the
     * naming convention. A foreign app squatting on our prefix is rejected too — failing closed on
     * an authority that is pretending to be ours is the safe direction.
     */
    private fun isOwnAuthority(authority: String?): Boolean {
        if (authority.isNullOrEmpty()) return false
        if (authority == packageName || authority.startsWith("$packageName.")) return true
        @Suppress("DEPRECATION")
        val info = runCatching { packageManager.resolveContentProvider(authority, 0) }.getOrNull()
        return info?.packageName == packageName
    }

    /**
     * Does [path] live inside app-private storage? CANONICALIZED on both sides, so neither `..`
     * segments nor the `/data/data` → `/data/user/0` symlink can walk around it, and FAILING CLOSED
     * on an empty path or a canonicalization error — a path we cannot even resolve is not one we
     * should be opening with our own uid.
     */
    private fun isAppPrivatePath(path: String?): Boolean {
        if (path.isNullOrEmpty()) return true
        val target = runCatching { File(path).canonicalPath }.getOrNull() ?: return true
        return appPrivateRoots().any { root -> target == root || target.startsWith("$root/") }
    }

    /**
     * Both internal roots plus the app-private directories on every external volume.
     *
     * `deviceProtectedDataDir` (`/data/user_de/<user>/<package>`) is a SECOND, distinct internal
     * root, not a subdirectory of [ApplicationInfo.dataDir]. Nothing in this app stores there yet;
     * it is listed so the guard does not quietly stop covering "our own storage" the day something
     * does.
     */
    private fun appPrivateRoots(): List<String> = buildList {
        fun add(file: File?) {
            runCatching { file?.canonicalPath }.getOrNull()?.let { add(it) }
        }
        add(File(applicationInfo.dataDir))
        applicationInfo.deviceProtectedDataDir?.let { add(File(it)) }
        add(filesDir)
        add(cacheDir)
        add(noBackupFilesDir)
        add(externalCacheDir)
        runCatching { getExternalFilesDirs(null) }.getOrNull()?.forEach(::add)
    }

    /**
     * NEW_TASK is REQUIRED: an externally-started activity runs in the SENDER's task, so CLEAR_TOP
     * alone would target the wrong task and stack a second MainActivity over an open reader (D2).
     */
    private fun handoffIntent(): Intent = Intent(this, MainActivity::class.java).addFlags(
        Intent.FLAG_ACTIVITY_NEW_TASK or
            Intent.FLAG_ACTIVITY_CLEAR_TOP or
            Intent.FLAG_ACTIVITY_SINGLE_TOP,
    )

    private fun unreadable() = IncomingItem.PreResolved(IncomingImportOutcome.Unreadable)

    private fun failed() = IncomingItem.PreResolved(IncomingImportOutcome.Failed)

    /** The fd is the provider's to release; a stream that refuses is nothing we can act on. */
    private fun closeQuietly(stream: InputStream) {
        try {
            stream.close()
        } catch (e: Throwable) {
            if (e.isFatal()) throw e
        }
    }

    companion object {
        /**
         * Free space required BEYOND the declared size before a stream is opened. The copy itself
         * is guarded post-open by the coordinator's counting stream; this only avoids starting an
         * import that obviously cannot fit.
         */
        const val FREE_SPACE_HEADROOM_BYTES = 32L * 1024 * 1024

        /**
         * TEST-ONLY dependency substitution, honored ONLY in a debuggable build (an exported entry
         * point must not carry a live override hook into a release APK). Null in production; set
         * and cleared by the connected test, which cannot declare a hostile ContentProvider of its
         * own. See [ImportDependencies].
         */
        @VisibleForTesting
        @Volatile
        @JvmStatic
        var testDependencies: ((ImportActivity) -> ImportDependencies)? = null

        private const val PEEK = "incoming-peek"
        private const val RESOLVE = "incoming-resolve"
        private const val MAX_CAUSE_DEPTH = 8

        /**
         * The most URIs a single inbound intent may contribute. A share sheet can hand
         * over an arbitrarily large selection; every extractor below stops COLLECTING at
         * this many rather than materialising the sender's whole payload and truncating
         * afterwards, so a hostile batch costs at most 20 references.
         */
        const val MAX_BATCH = 20

        /**
         * The most payload entries any extractor will LOOK AT, whether or not they turn
         * out to be URIs.
         *
         * [MAX_BATCH] alone bounds a dense payload but not a sparse one: 100 000
         * URI-less `ClipData` items would still be walked one by one. This is the
         * separate work bound for that case. It is 10x [MAX_BATCH] so a legitimately
         * mixed share (URIs interleaved with text items) still finds its books, while a
         * hostile sender's cost stays constant.
         */
        const val MAX_SCANNED_ITEMS = 200

        /**
         * Every URI an inbound intent carries, in sender order, capped at [MAX_BATCH].
         *
         * `VIEW` carries its payload in `intent.data`; `SEND` / `SEND_MULTIPLE` carry it
         * in `EXTRA_STREAM`, falling back to `ClipData` (some senders populate only the
         * clip). Returns an empty list for a missing, empty, or wrongly-typed payload —
         * this NEVER throws, because an exported entry point must survive anything a
         * hostile or merely sloppy sender puts in the intent.
         */
        fun urisFrom(intent: Intent?): List<Uri> {
            if (intent == null) return emptyList()
            return when (intent.action) {
                Intent.ACTION_VIEW -> listOfNotNull(intent.data)
                Intent.ACTION_SEND -> singleStreamUri(intent)?.let { listOf(it) } ?: clipUris(intent)
                Intent.ACTION_SEND_MULTIPLE -> multiStreamUris(intent).ifEmpty { clipUris(intent) }
                else -> emptyList()
            }
        }

        /** `EXTRA_STREAM` as a single Uri; null when absent OR present with another type. */
        private fun singleStreamUri(intent: Intent): Uri? = runCatching {
            IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
        }.getOrNull()

        /**
         * `EXTRA_STREAM` as a list of at most [MAX_BATCH] URIs.
         *
         * The list is requested as `Parcelable`, not `Uri`, on purpose: `IntentCompat`
         * has two implementations (a plain unchecked cast below API 34, the type-checked
         * platform call above it), and asking for `Uri` lets the newer one reject a
         * mixed-type list wholesale. Asking for the base type makes both behave alike and
         * leaves the per-element filtering here, where a stray member is skipped rather
         * than fatal. Iterating as `Any?` also avoids a per-element checked cast.
         */
        private fun multiStreamUris(intent: Intent): List<Uri> {
            val raw: List<Any?> = runCatching {
                IntentCompat.getParcelableArrayListExtra(intent, Intent.EXTRA_STREAM, Parcelable::class.java)
            }.getOrNull() ?: return emptyList()
            val out = ArrayList<Uri>()
            var scanned = 0
            for (item in raw) {
                if (out.size >= MAX_BATCH || scanned >= MAX_SCANNED_ITEMS) break
                scanned++
                if (item is Uri) out.add(item)
            }
            return out
        }

        /**
         * ClipData items that actually carry a Uri (a text item contributes nothing).
         *
         * Each item is read under its own guard so one malformed entry skips itself
         * instead of discarding the valid URIs around it.
         */
        private fun clipUris(intent: Intent): List<Uri> {
            val clip = runCatching { intent.clipData }.getOrNull() ?: return emptyList()
            val count = runCatching { clip.itemCount }.getOrNull() ?: return emptyList()
            val out = ArrayList<Uri>()
            var index = 0
            while (index < count && index < MAX_SCANNED_ITEMS && out.size < MAX_BATCH) {
                runCatching { clip.getItemAt(index)?.uri }.getOrNull()?.let { out.add(it) }
                index++
            }
            return out
        }
    }
}
