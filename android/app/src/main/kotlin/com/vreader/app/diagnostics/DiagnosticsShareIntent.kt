// Purpose: feature #164 WI-7 — build + launch the "share the diagnostics export" ACTION_SEND flow.
// Given a file that is physically inside `filesDir/diagnostics`, produce a chooser intent carrying
// a DiagnosticsFileProvider content URI on EXTRA_STREAM, `text/plain`, a read grant
// (FLAG_GRANT_READ_URI_PERMISSION) AND a matching ClipData (the flag alone can miss on receivers
// that read the clip), wrapped in Intent.createChooser.
//
// Security: the file MUST resolve — canonically, so `diagnostics/../elsewhere` does not pass — to a
// readable, existing path inside `filesDir/diagnostics`. Anything else yields a null intent and a
// silent no-op: never a crash, and never an invented error surface (rule 51). This guard is its
// OWN, deliberately not a widened `BookShareIntent.isInsideBooksDir`: one predicate covering two
// directories is one edit away from granting either feature's files through the other's provider,
// which is the same separation section 6.4 argues for at the provider level.
//
// @coordinates-with DiagnosticsFileProvider.kt (the authority), DiagnosticsExportWriter.kt (writes
//   the file, owns DIRECTORY_NAME), AndroidManifest.xml (the <provider> declaration).
package com.vreader.app.diagnostics

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Context
import android.content.Intent
import androidx.core.content.FileProvider
import java.io.File

private const val TAG = "DiagnosticsShare"
private const val DIAGNOSTICS_PROVIDER_SUFFIX = ".diagnosticsprovider"

/** The export is redacted plain text; a receiver should treat it as such. */
private const val EXPORT_MIME = "text/plain"

/**
 * Build the "Share diagnostics" chooser intent for [file], or `null` when [file] is not a shareable
 * export. Returns null (the silent no-op signal) when the file does not exist / is not readable, is
 * NOT canonically inside `filesDir/diagnostics`, or the FileProvider rejects the path.
 */
fun shareDiagnosticsIntent(context: Context, file: File): Intent? {
    if (!file.exists() || !file.isFile || !file.canRead()) return null
    if (!isInsideDiagnosticsDir(context, file)) return null

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

private fun File.canonicalPathOrSelf(): String =
    try { canonicalPath } catch (_: Exception) { absolutePath }
