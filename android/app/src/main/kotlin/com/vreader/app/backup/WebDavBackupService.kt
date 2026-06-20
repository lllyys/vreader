// Purpose: feature #116 WI-5b (#110 Phase 3) — the real BackupService backed by a WebDAV server.
// Implements the #114 UI seam (no ZIP/blob/PROPFIND concepts leak to the UI) over WebDavServerStore
// (credentials), BackupCollector (#116 WI-3), BackupArchive (WI-2), RestoreImporter (WI-4), and a
// WebDavTransport (WI-1). Remote layout is byte-for-byte the iOS materializing-restore:
// VReader/backups/<ts>_<id>.vreader.zip (sections+manifest, NO blobs) + VReader/books/<format>/...
// (content-addressed blob store, atomic PUT→MOVE, PROPFIND-deduped). backupId is opaque serverId/zip.
package com.vreader.app.backup

import com.vreader.app.backup.archive.BackupArchiveReader
import com.vreader.app.backup.archive.BackupArchiveWriter
import com.vreader.app.backup.archive.BlobPath
import com.vreader.app.backup.net.WebDavErrorKind
import com.vreader.app.backup.net.WebDavException
import com.vreader.app.backup.net.WebDavServerStore
import com.vreader.app.backup.net.WebDavTransport
import com.vreader.app.data.BookImporter
import com.vreader.app.data.LibraryRepository
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import vreader.contracts.backup.BackupMetadata
import java.io.File
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

class WebDavBackupService(
    private val serverStore: WebDavServerStore,
    private val repository: LibraryRepository,
    private val bookImporter: BookImporter,
    private val collector: BackupCollector,
    private val deviceName: String,
    private val appVersion: String,
    private val transportFactory: (String, String, String) -> WebDavTransport,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
    private val now: () -> Instant = Instant::now,
    private val newBackupId: () -> String = { java.util.UUID.randomUUID().toString() },
    private val zone: ZoneId = ZoneId.systemDefault(),
) : BackupService {

    override suspend fun listServers(): List<ServerSummary> = serverStore.list().map {
        ServerSummary(it.id, it.name, it.baseUrl, ServerStatus.unknown, "Not tested", it.wifiOnly)
    }

    override suspend fun testConnection(draft: ServerDraft): TestResult {
        val client = transportFactory(draft.baseUrl, draft.username, draft.password)
        return try {
            val entries = try {
                client.propfind(BACKUPS_DIR)
            } catch (e: WebDavException) {
                if (e.kind == WebDavErrorKind.notFound404) {
                    client.propfind("")  // root reachable but no backups dir yet — confirm the root
                    return TestResult.Ok("Connected — no backups yet.")
                }
                throw e
            }
            val n = entries.count { isBackupZip(it.isCollection, it.href) }
            TestResult.Ok("Connected — found an existing /vreader folder with $n backup${plural(n)}.")
        } catch (e: WebDavException) {
            TestResult.Fail(toUiError(e.kind), userMessage(e.kind))
        }
    }

    override suspend fun listBackups(serverId: String): BackupListResult {
        val client = clientFor(serverId)
        return try {
            val entries = try {
                client.propfind(BACKUPS_DIR)
            } catch (e: WebDavException) {
                if (e.kind == WebDavErrorKind.notFound404) return BackupListResult.Ok(emptyList())
                throw e
            }
            val metas = entries.filter { isBackupZip(it.isCollection, it.href) }.mapNotNull { entry ->
                val zipPath = "$BACKUPS_DIR/${fileName(entry.href)}"
                val bytes = client.get(zipPath)  // a WebDavException here escapes → outer catch → Error
                // Tolerate ONLY a parse failure (a corrupt ZIP is skipped, not the whole list).
                runCatching { BackupArchiveReader.read(bytes).metadata }.getOrNull()?.let { zipPath to it }
            }.sortedByDescending { it.second.createdAt }
            BackupListResult.Ok(metas.mapIndexed { i, (zipPath, meta) ->
                BackupSummary(
                    id = encodeBackupId(serverId, zipPath),
                    whenLabel = whenLabel(meta.createdAt),
                    sizeLabel = sizeLabel(meta.totalSizeBytes),
                    device = meta.deviceName,
                    books = meta.bookCount,
                    latest = i == 0,
                )
            })
        } catch (e: WebDavException) {
            BackupListResult.Error(toUiError(e.kind))
        }
    }

    override fun startBackup(serverId: String): Flow<BackupProgress> = flow {
        val client = clientFor(serverId)
        val collected = collector.collect(deviceName, appVersion, newBackupId(), now())
        val total = collected.blobs.size
        emit(BackupProgress(0, total))
        ensureCollection(client, BlobPath.BOOKS_ROOT)
        ensureCollection(client, BACKUPS_DIR)
        collected.blobs.forEachIndexed { i, blob ->
            ensureCollection(client, blob.blobPath.substringBeforeLast('/'))
            if (!client.exists(blob.blobPath)) {  // PROPFIND-dedupe: only NEW blobs transfer
                publishAtomically(client, blob.blobPath) { tmp -> client.putFile(tmp, File(blob.localFilePath)) }
            }
            emit(BackupProgress(i + 1, total))
        }
        // The ZIP is published atomically too — a failed/interrupted upload must never appear as a
        // listable (malformed) backup.
        val zip = BackupArchiveWriter.write(collected.metadata, collected.manifest, collected.sections)
        publishAtomically(client, "$BACKUPS_DIR/${zipName(collected.metadata)}") { tmp -> client.put(tmp, zip) }
    }.flowOn(ioDispatcher)

    /** PUT to a `.tmp` then MOVE into [path] (atomic publish). On any failure/cancellation before
     *  the MOVE, the `.tmp` is deleted under NonCancellable so no orphan is left. */
    private suspend fun publishAtomically(client: WebDavTransport, path: String, upload: suspend (String) -> Unit) {
        val tmp = "$path.tmp"
        var moved = false
        try {
            upload(tmp)
            client.move(tmp, path)
            moved = true
        } finally {
            if (!moved) withContext(NonCancellable) { runCatching { client.delete(tmp) } }
        }
    }

    override suspend fun loadManifest(backupId: String): List<ManifestBook> {
        val (serverId, zipPath) = decodeBackupId(backupId)
        val client = clientFor(serverId)
        val reader = BackupArchiveReader.read(client.get(zipPath))
        val localKeys = repository.listBooks().mapTo(HashSet()) { it.fingerprintKey }
        return reader.manifest.books.map { e ->
            ManifestBook(
                id = e.fingerprintKey,
                title = e.title ?: e.fingerprintKey,
                author = e.author,
                sizeLabel = sizeLabel(e.byteCount),
                state = if (e.fingerprintKey in localKeys) BookState.local else BookState.remote,
            )
        }
    }

    override fun restore(backupId: String, selection: Set<String>): Flow<RestoreProgress> = channelFlow {
        val (serverId, zipPath) = decodeBackupId(backupId)
        val client = clientFor(serverId)
        val reader = BackupArchiveReader.read(client.get(zipPath))
        val sel = selection.ifEmpty { null }  // empty selection = restore all
        val books = reader.manifest.books.filter { sel == null || it.fingerprintKey in sel }
        val importer = RestoreImporter(bookImporter, repository, client::getStream, ioDispatcher)
        val result = importer.restore(reader, selection = sel) { done, t ->
            val title = books.getOrNull(done - 1)?.let { it.title ?: it.fingerprintKey } ?: ""
            send(RestoreProgress.InProgress(done, t, title))  // suspending send — no dropped events
        }
        val outcome = when {
            result.restored.isEmpty() -> RestoreOutcome.failed
            result.failed.isEmpty() -> RestoreOutcome.success
            else -> RestoreOutcome.partial
        }
        send(RestoreProgress.Result(outcome, result.restored.size, books.size, result.failed.size, whenLabel(reader.metadata.createdAt)))
        // The block returns here → channelFlow closes the channel; no awaitClose (not callback-based).
    }.flowOn(ioDispatcher)

    override suspend fun retryBook(backupId: String, bookId: String): BookRestoreResult {
        val (serverId, zipPath) = decodeBackupId(backupId)
        val client = clientFor(serverId)
        val reader = BackupArchiveReader.read(client.get(zipPath))
        val importer = RestoreImporter(bookImporter, repository, client::getStream, ioDispatcher)
        val result = importer.restore(reader, selection = setOf(bookId))
        return if (bookId in result.restored) BookRestoreResult.restored else BookRestoreResult.failed
    }

    // ── helpers ────────────────────────────────────────────────

    private suspend fun clientFor(serverId: String): WebDavTransport {
        val profile = serverStore.list().firstOrNull { it.id == serverId }
            ?: throw IllegalArgumentException("unknown server $serverId")
        return transportFactory(profile.baseUrl, profile.username, serverStore.password(serverId) ?: "")
    }

    /** mkcol each ancestor of [path] (mkcol tolerates 405 = already exists). */
    private suspend fun ensureCollection(client: WebDavTransport, path: String) {
        var acc = ""
        for (segment in path.split('/').filter { it.isNotEmpty() }) {
            acc = if (acc.isEmpty()) segment else "$acc/$segment"
            client.mkcol(acc)
        }
    }

    private fun isBackupZip(isCollection: Boolean, href: String) = !isCollection && href.endsWith(BACKUP_EXT)
    private fun fileName(href: String) = href.trimEnd('/').substringAfterLast('/')
    private fun zipName(meta: BackupMetadata) = "${meta.createdAt.toEpochMilli()}_${meta.id}$BACKUP_EXT"

    private fun encodeBackupId(serverId: String, zipPath: String) = "$serverId/$zipPath"
    private fun decodeBackupId(backupId: String): Pair<String, String> {
        val slash = backupId.indexOf('/')  // serverId is a UUID (no '/'); the rest is the zip path
        require(slash > 0) { "malformed backupId: $backupId" }
        return backupId.substring(0, slash) to backupId.substring(slash + 1)
    }

    private fun whenLabel(instant: Instant): String = WHEN_FORMAT.withZone(zone).format(instant)
    private fun sizeLabel(bytes: Long): String = when {
        bytes >= 1_000_000 -> String.format(Locale.US, "%.1f MB", bytes / 1_000_000.0)
        bytes >= 1_000 -> String.format(Locale.US, "%.0f KB", bytes / 1_000.0)
        else -> "$bytes B"
    }

    private fun toUiError(kind: WebDavErrorKind): WebDavError = when (kind) {
        WebDavErrorKind.auth401 -> WebDavError.auth401
        WebDavErrorKind.notFound404 -> WebDavError.notFound404
        WebDavErrorKind.timeout -> WebDavError.timeout
        WebDavErrorKind.offline, WebDavErrorKind.server -> WebDavError.offline
    }

    private fun userMessage(kind: WebDavErrorKind): String = when (kind) {
        WebDavErrorKind.auth401 -> "Authentication failed — check the username and password."
        WebDavErrorKind.notFound404 -> "The server responded, but the path wasn't found."
        WebDavErrorKind.timeout -> "The server took too long to respond."
        WebDavErrorKind.offline, WebDavErrorKind.server -> "Couldn't reach the server."
    }

    private fun plural(n: Int) = if (n == 1) "" else "s"

    companion object {
        const val BACKUPS_DIR = "VReader/backups"
        private const val BACKUP_EXT = ".vreader.zip"
        private val WHEN_FORMAT = DateTimeFormatter.ofPattern("MMM d, h:mm a", Locale.US)
    }
}
