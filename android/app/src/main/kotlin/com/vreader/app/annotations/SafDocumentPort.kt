// Purpose: feature #165 WI-4b — the provider seam of the annotations import/export boundary: the
// THREE `ContentResolver` calls this feature is allowed to make, behind an interface, plus the one
// production adapter that actually makes them.
//
// Key decisions:
//  - EVERY METHOD HERE IS PRESUMED HOSTILE AND UNBOUNDED. `ContentResolver.query`,
//    `openInputStream` and `openOutputStream` are synchronous, uninterruptible, and run inside a
//    provider process an attacker may control: a provider that never returns parks the calling
//    thread forever, and `withContext(Dispatchers.IO)` only relocates that block without bounding
//    it. Nothing in this file bounds anything — it is deliberately the *unsafe* layer, invoked
//    ONLY from inside `AnnotationsIoController`'s `BoundedCallGate` calls (§8.1). That is why the
//    seam exists at all: it is what makes each of those three call sites individually reachable by
//    a JVM test that parks in it forever, which a concrete `ContentResolver` is not.
//  - It is an INTERFACE, not a lambda bundle, because the three calls share one lifetime and one
//    trust story; splitting them into unrelated function parameters would let a future caller wire
//    two of them from different sources.
//  - A refusal to open is a NULL RETURN, not an exception (`IncomingBookResolver.openOrNull`'s
//    precedent) — the caller maps it to a typed `Unreadable`, so "the provider said no" and "the
//    provider misbehaved" stay distinguishable.
//  - NO SANITIZATION AND NO VALIDATION HAPPEN HERE. `SafMetadata.displayName` is raw,
//    provider-controlled text; the controller sanitizes it at the boundary (§8.4) before it can
//    reach a pixel. Doing it here would hide the boundary in the adapter.
//
// @coordinates-with AnnotationsIoController (the only caller, and the only place these are
//   bounded), IncomingBookResolver (the same cursor projection, for books).
package com.vreader.app.annotations

import android.content.ContentResolver
import android.database.Cursor
import android.net.Uri
import android.provider.OpenableColumns
import java.io.FileNotFoundException
import java.io.InputStream
import java.io.OutputStream

/**
 * What a document provider claims about a picked document.
 *
 * [displayName] is RAW attacker-controlled text — it must be sanitized before it is shown or
 * stored. [declaredSize] is a CLAIM, not a fact: it may be absent, and it may lie in either
 * direction, so it is only ever used to refuse early, never to trust a read.
 */
data class SafMetadata(val displayName: String?, val declaredSize: Long?)

/**
 * The provider calls the annotations feature makes. **Every implementation may block forever**;
 * no method here may be invoked outside a `BoundedCallGate.call`.
 */
interface SafDocumentPort {

    /** `OpenableColumns.DISPLAY_NAME` + `SIZE`. A provider that answers nothing yields nulls. */
    fun queryMetadata(uri: Uri): SafMetadata

    /** Null when the provider refuses to open the document for reading. */
    fun openInput(uri: Uri): InputStream?

    /** Null when the provider refuses to open the destination for writing. */
    fun openOutput(uri: Uri): OutputStream?
}

/**
 * `AnnotationsImportReader.parse` as seen from the I/O boundary — the feature's second seam, and
 * here for the same reason as the first: what crosses it must be observable.
 *
 * It exists so a test can see what the boundary HANDS the reader, above all that the file name is
 * already sanitized (§8.4). Without it that guarantee is unobservable, because the reader
 * sanitizes again downstream and would keep an end-to-end assertion green even if the boundary
 * stopped sanitizing entirely — measured: that mutation survived until this seam existed.
 */
fun interface AnnotationsParser {
    fun parse(
        input: InputStream,
        fileName: String,
        bookKey: String,
        bookTitle: String,
        existing: ExistingAnnotationState,
    ): ImportParseResult
}

/**
 * The production adapter — the ONLY `ContentResolver` touch in this feature.
 *
 * Its three methods are unbounded by construction and are called exclusively from
 * `AnnotationsIoController`, each inside its own bounded call. Keeping them in one small class is
 * what makes "every provider call in `annotations/` is bounded" checkable by reading one file
 * instead of grepping a package.
 */
class ContentResolverSafPort(private val contentResolver: ContentResolver) : SafDocumentPort {

    override fun queryMetadata(uri: Uri): SafMetadata {
        val projection = arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        contentResolver.query(uri, projection, null, null, null)?.use { cursor ->
            if (!cursor.moveToFirst()) return SafMetadata(null, null)
            return SafMetadata(
                displayName = cursor.stringOrNull(OpenableColumns.DISPLAY_NAME),
                // A negative size is "unknown", not a real claim — treat it as absent rather than
                // letting it slip past a `> cap` preflight as if the provider had promised small.
                declaredSize = cursor.longOrNull(OpenableColumns.SIZE)?.takeIf { it >= 0 },
            )
        }
        return SafMetadata(null, null)
    }

    override fun openInput(uri: Uri): InputStream? = try {
        contentResolver.openInputStream(uri)
    } catch (e: FileNotFoundException) {
        null
    }

    override fun openOutput(uri: Uri): OutputStream? = try {
        contentResolver.openOutputStream(uri)
    } catch (e: FileNotFoundException) {
        null
    }

    private fun Cursor.stringOrNull(column: String): String? {
        val index = getColumnIndex(column)
        return if (index >= 0 && !isNull(index)) getString(index) else null
    }

    private fun Cursor.longOrNull(column: String): Long? {
        val index = getColumnIndex(column)
        return if (index >= 0 && !isNull(index)) getLong(index) else null
    }
}
