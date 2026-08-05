// Purpose: feature #164 WI-7 — build + launch the "share the diagnostics export" ACTION_SEND flow.
// Given a file that is physically inside `filesDir/diagnostics`, produce a chooser intent carrying
// a DiagnosticsFileProvider content URI on EXTRA_STREAM, `text/plain`, a read grant
// (FLAG_GRANT_READ_URI_PERMISSION) AND a matching ClipData (the flag alone can miss on receivers
// that read the clip), wrapped in Intent.createChooser.
//
// Security: the file MUST resolve — canonically, so `diagnostics/../elsewhere` does not pass — to a
// readable, existing path inside `filesDir/diagnostics`, AND be a regular file with exactly one
// name on disk (a hard link is a second name for bytes that live elsewhere, which canonicalisation
// cannot see). Anything else yields a null intent and a silent no-op: never a crash, and never an
// invented error surface (rule 51). This guard is its OWN, deliberately not a widened
// `BookShareIntent.isInsideBooksDir`: one predicate covering two directories is one edit away from
// granting either feature's files through the other's provider, which is the same separation
// section 6.4 argues for at the provider level.
//
// @coordinates-with DiagnosticsFileProvider.kt (the authority), DiagnosticsExportWriter.kt (writes
//   the file, owns DIRECTORY_NAME), AndroidManifest.xml (the <provider> declaration).
package com.vreader.app.diagnostics

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import androidx.core.content.FileProvider
import java.io.File

private const val TAG = "DiagnosticsShare"
private const val DIAGNOSTICS_PROVIDER_SUFFIX = ".diagnosticsprovider"

/** The export is redacted plain text; a receiver should treat it as such. */
private const val EXPORT_MIME = "text/plain"

/**
 * Build the "Share diagnostics" chooser intent for [file], or `null` when [file] is not a shareable
 * export. Returns null (the silent no-op signal) when the file does not exist / is not readable,
 * is not NAMED like an export ([DiagnosticsExportWriter.isExportFileName]), is NOT canonically
 * inside `filesDir/diagnostics`, is an alias rather than a file of its own, or the FileProvider
 * rejects the path.
 *
 * The name check narrows this from "any file in the directory" to "a file this app's writer
 * produces" (Gate-4 round 2, High). It is a narrowing, not a proof of provenance: same-module code
 * that deliberately wrote raw bytes under an export's exact name could still share them. Closing
 * that last gap would mean replacing this file-taking API with a facade that only shares what it
 * just wrote — which is not this work item's specified surface, and is recorded as such rather than
 * quietly redesigned. What IS closed: every byte the writer produces has been through
 * [DiagnosticsRedactor] unconditionally, whatever renderer it was given.
 */
fun shareDiagnosticsIntent(context: Context, file: File): Intent? {
    if (!file.exists() || !file.isFile || !file.canRead()) return null
    if (!DiagnosticsExportWriter.isExportFileName(file.name)) return null
    if (!isInsideDiagnosticsDir(context, file)) return null
    if (!isUnaliasedRegularFile(file)) return null

    val authority = context.packageName + DIAGNOSTICS_PROVIDER_SUFFIX
    val uri = try {
        FileProvider.getUriForFile(context, authority, file)
    } catch (e: IllegalArgumentException) {
        // FileProvider throws when the file is outside every configured <paths> root — reject.
        VLog.w(DiagnosticsCategory.LIBRARY, TAG, "export not shareable via FileProvider (outside grant scope)", e)
        return null
    }

    val send = Intent(Intent.ACTION_SEND).apply {
        type = EXPORT_MIME
        putExtra(Intent.EXTRA_STREAM, uri)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        // The label is the machine-generated export filename — never invented user copy (rule 51).
        clipData = ClipData.newRawUri(file.name, uri)
    }
    return Intent.createChooser(send, null)
}

/**
 * Build + launch the share chooser for [file]. An out-of-scope/missing file, or a chooser with no
 * receiver at all ([ActivityNotFoundException]), is a SILENT no-op (logged) — never a crash and
 * never a visible error surface. The no-receiver guarantee lives HERE rather than on
 * [shareDiagnosticsIntent], which builds an Intent and therefore cannot throw it.
 */
fun shareDiagnostics(context: Context, file: File) {
    val chooser = (shareDiagnosticsIntent(context, file) ?: return).apply {
        // Launching from a non-Activity Context requires NEW_TASK; harmless from an Activity.
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    try {
        context.startActivity(chooser)
    } catch (e: ActivityNotFoundException) {
        VLog.w(DiagnosticsCategory.LIBRARY, TAG, "no activity to receive the diagnostics export", e)
    }
}

/**
 * True only when [file] resolves to a path physically inside `filesDir/diagnostics`.
 *
 * Canonical on both sides, so a `..` segment is resolved away before the comparison rather than
 * compared as text; the trailing separator stops a sibling directory whose name merely starts with
 * `diagnostics` from matching.
 */
private fun isInsideDiagnosticsDir(context: Context, file: File): Boolean {
    val dir = File(context.filesDir, DiagnosticsExportWriter.DIRECTORY_NAME)
    val dirCanonical = dir.canonicalPathOrSelf() + File.separator
    return file.canonicalPathOrSelf().startsWith(dirCanonical)
}

/**
 * True only when [file] is a plain regular file with exactly one name on disk.
 *
 * Canonicalisation resolves a SYMLINK, so a symlink out of the export directory is already
 * rejected above — but a HARD LINK has no target to resolve: it is a second name for the same
 * inode, and a link planted inside `diagnostics/` would let this function's own grant hand another
 * app bytes that live somewhere else entirely (Gate-4 round 1, High). `lstat` reports the link
 * itself rather than following it, so this rejects both shapes: anything that is not a regular file
 * (symlink, fifo, directory) and any regular file whose inode carries more than one name.
 *
 * Threat-model note, stated rather than implied: code running as this app's own uid can read those
 * bytes directly, so this is not a defence against a compromised process. What it removes is the
 * specific escalation where OUR read grant — the only thing that lets a DIFFERENT app read
 * app-private storage — is used to launder a file the grant was never scoped to. A genuine export
 * is created fresh by `DiagnosticsExportWriter` and always has a link count of one, so this can
 * never reject a real export.
 */
private fun isUnaliasedRegularFile(file: File): Boolean = try {
    val stat = Os.lstat(file.absolutePath)
    OsConstants.S_ISREG(stat.st_mode) && stat.st_nlink <= 1L
} catch (e: ErrnoException) {
    // Un-stattable is not shareable.
    false
}

private fun File.canonicalPathOrSelf(): String =
    try { canonicalPath } catch (_: Exception) { absolutePath }
