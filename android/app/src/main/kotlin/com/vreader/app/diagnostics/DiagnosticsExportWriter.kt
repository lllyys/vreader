package com.vreader.app.diagnostics

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException
import java.nio.charset.StandardCharsets
import java.nio.file.Files
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
 * - **The filename is DERIVED from the injected [clock], never supplied by a caller.** [write]
 *   takes the payload and nothing else, so there is no caller-controlled path component to
 *   sanitize — the traversal class of bug is removed rather than defended against. The resolved
 *   file is still asserted to be a canonical child of [dir] before anything is written: that check
 *   is defence in depth against a future refactor reintroducing an input here, not a guard against
 *   today's derivation.
 * - **Temp + atomic rename, the `BookImporter.importStream` precedent.** A reader that opens the
 *   export concurrently with a re-export must see either the whole old file or the whole new one;
 *   writing straight into the live name would expose a truncated payload. The temp file is created
 *   inside [dir] so the rename stays within one filesystem, and a `finally` deletes it on every
 *   failure path — a `.part` file surviving a crash is itself pruned by the next write.
 * - **The directory holds AT MOST ONE export.** Diagnostics exports are disposable: the user shares
 *   one and moves on. Keeping history would grow app-private storage without bound for a payload
 *   nobody reads twice, and — because the whole point of the file is that it leaves the device —
 *   every retained copy is redacted-but-still-sensitive text sitting around longer than it needs
 *   to. Pruning happens AFTER the promote, so a failed write never destroys the previous export.
 * - **The single-file rule is what makes [DIRECTORY_NAME] load-bearing.** It is the same string
 *   `res/xml/diagnostics_paths.xml` grants and the same one `shareDiagnosticsIntent`'s path guard
 *   checks; a drift between them would silently turn every share into a no-op, so all three read
 *   this constant or the xml that mirrors it (the connected test asserts the round trip on device).
 *
 * Known limitations (accepted, not mitigated):
 * - **Concurrent writes are not serialised.** Two overlapping [write] calls can each prune the
 *   other's promoted file, and the loser's returned `File` may no longer exist. Exports are
 *   user-initiated from a single screen with a single share affordance, so the flow is
 *   single-flight by construction; adding a mutex here would imply a concurrency story the caller
 *   does not have.
 * - **The date derivation is duplicated in [DiagnosticsViewModel.exportFileName]**, which names the
 *   same export for the UI. Single-sourcing it would mean the viewer's label reaching into the
 *   writer (or vice versa) purely for a formatter. Instead `DiagnosticsExportWriterTest` pins the
 *   two together with a differential assertion over several instants, so a drift fails a test
 *   rather than shipping a file whose name disagrees with what the user was shown.
 *
 * @coordinates-with DiagnosticsShareIntent.kt, DiagnosticsFileProvider.kt,
 *   `res/xml/diagnostics_paths.xml`, VReaderApp.kt (AppContainer builds it over filesDir)
 */
class DiagnosticsExportWriter(
    private val dir: File,
    /** Injected so the derived filename is deterministic in tests. */
    private val clock: () -> Long = System::currentTimeMillis,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
    /** Read per write, so a zone change between exports is picked up (the ViewModel's convention). */
    private val zone: () -> ZoneId = ZoneId::systemDefault,
) {

    /**
     * Writes [text] as UTF-8 into `<dir>/vreader-log-YYYY-MM-DD.txt`, replacing any previous
     * export, and returns the promoted file.
     *
     * @throws IOException if the directory cannot be created or the payload cannot be written.
     */
    suspend fun write(text: String): File = withContext(ioDispatcher) {
        if (!dir.isDirectory && !dir.mkdirs() && !dir.isDirectory) {
            throw IOException("diagnostics export directory could not be created")
        }
        val target = resolveTarget(fileNameAt(clock()))

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

    /** Drops every other file in [dir] — prior exports and any temp artifact a crash left behind. */
    private fun pruneAllBut(target: File) {
        val keep = target.canonicalPathOrSelf()
        dir.listFiles()?.forEach { candidate ->
            if (candidate.canonicalPathOrSelf() != keep) candidate.deleteRecursively()
        }
    }

    private fun File.canonicalPathOrSelf(): String =
        try { canonicalPath } catch (_: Exception) { absolutePath }

    companion object {
        /**
         * The export directory's name under `filesDir`. Mirrored by `res/xml/diagnostics_paths.xml`
         * (`<files-path name="diagnostics" path="diagnostics/"/>`) — the FileProvider grants exactly
         * this directory, so the two must not drift.
         */
        const val DIRECTORY_NAME: String = "diagnostics"

        private const val FILE_PREFIX = "vreader-log-"
        private const val FILE_SUFFIX = ".txt"
        private const val TEMP_PREFIX = "export-"
        private const val TEMP_SUFFIX = ".part"

        /** `Locale.ROOT`: a machine-facing stamp must not pick up non-ASCII digits or a non-ISO era. */
        private val FILE_DATE: DateTimeFormatter =
            DateTimeFormatter.ofPattern("yyyy-MM-dd", Locale.ROOT)
    }
}
