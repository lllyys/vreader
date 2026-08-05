package com.vreader.app.diagnostics

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException
import java.nio.charset.StandardCharsets
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.StandardCopyOption
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/**
 * Purpose: Feature #164 WI-7 — puts the redacted diagnostics payload on disk so the share flow has
 * something to hand a receiver. One file, in one directory, replaced on every export.
 *
 * Key decisions:
 * - **It accepts ENTRIES, not text, and REDACTS what [renderPayload] returns.** The plan's section
 *   4.1 sketched `write(text: String)`; that shape makes redaction a caller convention, so
 *   `write("password=hunter2")` would be a legal call that lands an unredacted secret on disk and
 *   then in another app (Gate-4 round 1, High). Taking entries closed that door but left another —
 *   a caller could still inject a non-redacting [renderPayload] (Gate-4 round 2, High) — so the
 *   rendered payload goes through [DiagnosticsRedactor] here, unconditionally. Production wires
 *   [renderPayload] to [DiagnosticsLogStore.exportText], which has already redacted every message,
 *   and `redact` is idempotent by contract, so the extra pass changes nothing the store produces
 *   from this app's own entries (asserted as a fixed point in `DiagnosticsExportWriterTest`) and is
 *   the last word for every other path. The seam stays a function type so this file does not depend
 *   on the store. **Precisely** (Gate-4 round 3, Low): the store redacts message BODIES, and the
 *   entry header it wraps them in carries a raw category — which for a logcat-sourced entry is a
 *   third-party TAG this app does not choose. A credential-shaped tag would therefore be redacted
 *   by this pass and not by the store's. That is a difference in the safe direction, not corruption:
 *   the payload is a `String` throughout and is encoded to UTF-8 exactly once, after redaction.
 * - **The filename is DERIVED from the injected [clock], never supplied by a caller.** [write]
 *   takes the entries and nothing else, so there is no caller-controlled path component to
 *   sanitize — the traversal class of bug is removed rather than defended against. The resolved
 *   file is still asserted to be a canonical child of [dir] before anything is written: that check
 *   is defence in depth against a future refactor reintroducing an input here, not a guard against
 *   today's derivation.
 * - **One clock reading per export.** The payload header's `generated:` stamp and the filename's
 *   date come from the same instant, so an export written across midnight cannot claim one day in
 *   its name and another in its text.
 * - **Temp + atomic rename, the `BookImporter.importStream` precedent.** A reader that opens the
 *   export concurrently with a re-export must see either the whole old file or the whole new one;
 *   writing straight into the live name would expose a truncated payload. The temp file is created
 *   inside [dir] so the rename stays within one filesystem, and a `finally` deletes it on every
 *   failure path — a `.part` file surviving a crash is itself pruned by the next write.
 * - **The whole create -> write -> promote -> prune sequence holds [writeLock].** Unserialised, two
 *   overlapping exports can each prune the other's promoted file, so a caller could be handed a
 *   `File` that no longer exists (Gate-4 round 1, Medium). "Only one screen shares" is a claim
 *   about today's callers, not a property of this class, and rapid repeated taps are exactly the
 *   edge case that breaks it.
 * - **The directory holds AT MOST ONE export.** Diagnostics exports are disposable: the user shares
 *   one and moves on. Keeping history would grow app-private storage without bound for a payload
 *   nobody reads twice, and — because the whole point of the file is that it leaves the device —
 *   every retained copy is redacted-but-still-sensitive text sitting around longer than it needs
 *   to. Pruning happens AFTER the promote, so a failed write never destroys the previous export.
 * - **The prune matches by directory ENTRY NAME and never follows a link.** Canonicalising each
 *   candidate would let a symlink that resolves to the promoted file survive as a second entry
 *   (Gate-4 round 1, Medium), and a recursive delete is the wrong tool for a directory that only
 *   ever holds flat files — an unexpected subdirectory is reported, not erased.
 * - **The single-file rule is what makes [DIRECTORY_NAME] load-bearing.** It is the same string
 *   `res/xml/diagnostics_paths.xml` grants and the same one `shareDiagnosticsIntent`'s path guard
 *   checks; a drift between them would silently turn every share into a no-op, so all three read
 *   this constant or the xml that mirrors it (the connected test asserts the round trip on device).
 *
 * Known limitation (accepted, not mitigated): the date derivation is duplicated in
 * [DiagnosticsViewModel.exportFileName], which names the same export for the UI. Single-sourcing it
 * would mean the viewer's label reaching into the writer (or vice versa) purely for a formatter.
 * Instead `DiagnosticsExportWriterTest` pins the two together with a differential assertion over
 * several instants, so a drift fails a test rather than shipping a file whose name disagrees with
 * what the user was shown.
 *
 * @coordinates-with DiagnosticsShareIntent.kt, DiagnosticsFileProvider.kt, DiagnosticsLogStore.kt
 *   (supplies [renderPayload]), `res/xml/diagnostics_paths.xml`, VReaderApp.kt (AppContainer)
 */
class DiagnosticsExportWriter(
    private val dir: File,
    /**
     * Renders the entries into the shareable payload. Production wires
     * [DiagnosticsLogStore.exportText]. Whatever it returns is passed through
     * [DiagnosticsRedactor] before a byte is written, so this parameter cannot be used — by a test,
     * a future caller, or a mistake — to put an unredacted secret on disk.
     */
    private val renderPayload: (List<DiagnosticsLogEntry>, Long) -> String,
    /** Injected so the derived filename and the payload's stamp are deterministic in tests. */
    private val clock: () -> Long = System::currentTimeMillis,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
    /** Read per write, so a zone change between exports is picked up (the ViewModel's convention). */
    private val zone: () -> ZoneId = ZoneId::systemDefault,
) {

    /** Serialises the whole export so two callers cannot prune each other's promoted file. */
    private val writeLock = Mutex()

    /**
     * Renders [entries] through [renderPayload], REDACTS the result, writes it as UTF-8 into
     * `<dir>/vreader-log-YYYY-MM-DD.txt` replacing any previous export, and returns the promoted
     * file.
     *
     * Last-write-wins, stated rather than implied (Gate-4 round 2, Medium): the directory holds one
     * export, so a LATER export overwrites (same day) or prunes (different day) the file an earlier
     * call returned. The lock makes each export internally consistent — it does not freeze a
     * returned `File` for the caller's later use. A caller that must hand the file to another app
     * writes and shares it as one user action; keeping a returned file valid across an arbitrary
     * later export would require a per-share file, which contradicts the single-export policy.
     *
     * @throws IOException if the directory cannot be created or the payload cannot be written.
     * @throws IllegalStateException if the derived file would resolve outside [dir] — a programming
     *   error (the name is derived internally), so it fails loudly rather than writing anywhere.
     */
    suspend fun write(entries: List<DiagnosticsLogEntry>): File = withContext(ioDispatcher) {
        writeLock.withLock {
            if (!dir.isDirectory && !dir.mkdirs() && !dir.isDirectory) {
                throw IOException("diagnostics export directory could not be created")
            }
            // ONE reading: the filename's date and the payload's `generated:` stamp agree by
            // construction rather than by luck.
            val now = clock()
            // Unconditional: no renderer, injected or wired, decides whether a secret reaches disk.
            val text = DiagnosticsRedactor.redact(renderPayload(entries, now))
            val target = resolveTarget(fileNameAt(now))

            val temp = File.createTempFile(TEMP_PREFIX, TEMP_SUFFIX, dir)
            try {
                temp.writeBytes(text.toByteArray(StandardCharsets.UTF_8))
                promoteAtomically(temp, target)
            } finally {
                // A failed write (or a successful move) leaves no .part behind.
                if (temp.exists()) temp.delete()
            }

            // Only after the promote succeeded: a throw above must never cost the previous export.
            pruneAllBut(target)
            target
        }
    }

    /**
     * The export file for [fileName], proven to be a canonical child of [dir].
     *
     * [fileName] is derived internally today, so this can only fail if a refactor reintroduces
     * caller influence over the path — which is exactly when it should fail loudly.
     */
    private fun resolveTarget(fileName: String): File {
        val target = File(dir, fileName)
        val resolvedParent = target.canonicalFile.parentFile
        check(resolvedParent == dir.canonicalFile) {
            "diagnostics export resolved outside its directory"
        }
        return target
    }

    private fun fileNameAt(millis: Long): String =
        FILE_PREFIX + FILE_DATE.format(Instant.ofEpochMilli(millis).atZone(zone())) + FILE_SUFFIX

    /**
     * Swaps [temp] into [target] as a single rename — never delete-then-copy into the live path, so
     * a concurrent reader never observes a partial export (the `BookImporter` precedent).
     */
    private fun promoteAtomically(temp: File, target: File) {
        try {
            Files.move(
                temp.toPath(), target.toPath(),
                StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING,
            )
        } catch (e: java.nio.file.AtomicMoveNotSupportedException) {
            // Same-directory move is still one rename on a filesystem without ATOMIC_MOVE support.
            Files.move(temp.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
    }

    /**
     * Drops every other DIRECTORY ENTRY — prior exports, and any temp artifact a crash left behind.
     *
     * Matching on the entry name (not the canonical path) is deliberate: a symlink resolving to the
     * promoted file has the SAME canonical path, so canonical matching would keep it and leave two
     * entries in a directory documented to hold one.
     *
     * `Files.deleteIfExists` is used for EVERY entry, directories included: it removes an empty
     * directory and refuses a non-empty one, which is exactly the wanted behaviour — nothing is
     * ever recursed into and no link is ever followed. An entry that survives is reported through
     * [VLog] rather than escalated, because the export itself already succeeded and failing here
     * would throw away a good file. The residual check is `NOFOLLOW_LINKS` so a DANGLING symlink
     * (whose `File.exists()` is false while its directory entry is very much still there) is
     * reported rather than silently passed over.
     */
    private fun pruneAllBut(target: File) {
        val keep = target.name
        val leftovers = dir.list()?.filter { it != keep }.orEmpty()
        for (name in leftovers) {
            val path = File(dir, name).toPath()
            try {
                Files.deleteIfExists(path)
            } catch (e: IOException) {
                // A non-empty directory (DirectoryNotEmptyException) or an un-deletable entry.
            }
            if (Files.exists(path, LinkOption.NOFOLLOW_LINKS)) {
                VLog.w(
                    DiagnosticsCategory.LIBRARY, TAG,
                    "diagnostics export directory still holds an unexpected entry after pruning: $name",
                )
            }
        }
    }

    companion object {
        private const val TAG = "DiagnosticsExport"

        /**
         * The export directory's name under `filesDir`. Mirrored by `res/xml/diagnostics_paths.xml`
         * (`<files-path name="diagnostics" path="diagnostics/"/>`) — the FileProvider grants exactly
         * this directory, so the two must not drift.
         */
        const val DIRECTORY_NAME: String = "diagnostics"

        private const val FILE_PREFIX = "vreader-log-"
        private const val FILE_SUFFIX = ".txt"

        /**
         * The shape every name [write] derives has, and the ONLY shape the share path will grant a
         * URI for. Single-sourced here so the writer's naming and the share guard cannot drift; a
         * file that some other code dropped into the export directory under its own name is not an
         * export and is not shareable.
         */
        private val EXPORT_NAME = Regex("^vreader-log-\\d{4}-\\d{2}-\\d{2}\\.txt$")

        /** True when [name] is the name of an export this writer produces. */
        fun isExportFileName(name: String): Boolean = EXPORT_NAME.matches(name)
        private const val TEMP_PREFIX = "export-"
        private const val TEMP_SUFFIX = ".part"

        /** `Locale.ROOT`: a machine-facing stamp must not pick up non-ASCII digits or a non-ISO era. */
        private val FILE_DATE: DateTimeFormatter =
            DateTimeFormatter.ofPattern("yyyy-MM-dd", Locale.ROOT)
    }
}
