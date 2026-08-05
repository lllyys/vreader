// Purpose: feature #155 WI-2 — `ImportActivity.urisFrom(intent)`, the pure payload
// extractor for every inbound shape (VIEW / SEND / SEND_MULTIPLE, EXTRA_STREAM or
// ClipData), including the hostile ones: a wrong-typed extra, a list holding
// non-Uri members, and an oversized batch. The contract under test is that it
// NEVER throws and never returns more than MAX_BATCH.
//
// Runs on the JVM via Robolectric (Intent/Uri/ClipData need the Android runtime).
package com.vreader.app.imports

import android.content.ClipData
import android.content.Intent
import android.net.Uri
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class ImportActivityUriExtractionTest {

    private fun uri(n: Int) = Uri.parse("content://com.example.provider/doc/$n.epub")

    private fun clipOf(vararg uris: Uri): ClipData {
        val clip = ClipData.newRawUri("books", uris.first())
        uris.drop(1).forEach { clip.addItem(ClipData.Item(it)) }
        return clip
    }

    // ---- VIEW ----

    @Test
    fun view_returnsTheIntentData() {
        val intent = Intent(Intent.ACTION_VIEW, uri(1))
        assertEquals(listOf(uri(1)), ImportActivity.urisFrom(intent))
    }

    @Test
    fun view_withNoData_returnsEmpty() {
        assertEquals(emptyList<Uri>(), ImportActivity.urisFrom(Intent(Intent.ACTION_VIEW)))
    }

    // ---- SEND ----

    @Test
    fun send_returnsTheExtraStreamUri() {
        val intent = Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, uri(2))
        assertEquals(listOf(uri(2)), ImportActivity.urisFrom(intent))
    }

    @Test
    fun send_withoutExtraStream_fallsBackToClipData() {
        val intent = Intent(Intent.ACTION_SEND).apply { clipData = clipOf(uri(3)) }
        assertEquals(listOf(uri(3)), ImportActivity.urisFrom(intent))
    }

    @Test
    fun send_withNeitherExtraNorClip_returnsEmpty() {
        // The plain-text-snippet share: no file payload at all.
        val intent = Intent(Intent.ACTION_SEND)
            .setType("text/plain")
            .putExtra(Intent.EXTRA_TEXT, "just some prose")
        assertEquals(emptyList<Uri>(), ImportActivity.urisFrom(intent))
    }

    @Test
    fun send_withWronglyTypedExtra_doesNotThrow_andFallsBackToClipData() {
        // A sender that puts a String (or anything not a Uri) under EXTRA_STREAM.
        val intent = Intent(Intent.ACTION_SEND)
            .putExtra(Intent.EXTRA_STREAM, "not-a-uri")
            .apply { clipData = clipOf(uri(4)) }
        assertEquals(listOf(uri(4)), ImportActivity.urisFrom(intent))
    }

    @Test
    fun send_withWronglyTypedExtraAndNoClip_returnsEmpty() {
        val intent = Intent(Intent.ACTION_SEND).putExtra(Intent.EXTRA_STREAM, 42)
        assertEquals(emptyList<Uri>(), ImportActivity.urisFrom(intent))
    }

    // ---- SEND_MULTIPLE ----

    @Test
    fun sendMultiple_returnsTheExtraStreamList() {
        val payload = arrayListOf(uri(5), uri(6), uri(7))
        val intent = Intent(Intent.ACTION_SEND_MULTIPLE)
            .putParcelableArrayListExtra(Intent.EXTRA_STREAM, payload)
        assertEquals(payload.toList(), ImportActivity.urisFrom(intent))
    }

    @Test
    fun sendMultiple_withoutExtraStream_fallsBackToClipData() {
        val intent = Intent(Intent.ACTION_SEND_MULTIPLE).apply { clipData = clipOf(uri(8), uri(9)) }
        assertEquals(listOf(uri(8), uri(9)), ImportActivity.urisFrom(intent))
    }

    @Test
    fun sendMultiple_withEmptyExtraStreamList_fallsBackToClipData() {
        val intent = Intent(Intent.ACTION_SEND_MULTIPLE)
            .putParcelableArrayListExtra(Intent.EXTRA_STREAM, arrayListOf())
            .apply { clipData = clipOf(uri(10)) }
        assertEquals(listOf(uri(10)), ImportActivity.urisFrom(intent))
    }

    @Test
    fun sendMultiple_withWronglyTypedExtra_doesNotThrow() {
        val intent = Intent(Intent.ACTION_SEND_MULTIPLE).putExtra(Intent.EXTRA_STREAM, "not-a-list")
        assertEquals(emptyList<Uri>(), ImportActivity.urisFrom(intent))
    }

    // ---- caps, blanks, and the never-throws contract ----

    @Test
    fun batchIsCappedAtMaxBatch() {
        val payload = ArrayList<Uri>((1..25).map { uri(it) })
        val intent = Intent(Intent.ACTION_SEND_MULTIPLE)
            .putParcelableArrayListExtra(Intent.EXTRA_STREAM, payload)
        val result = ImportActivity.urisFrom(intent)
        assertEquals(ImportActivity.MAX_BATCH, result.size)
        assertEquals(payload.take(ImportActivity.MAX_BATCH), result)
    }

    @Test
    fun oversizedClipDataIsAlsoCapped() {
        val uris = (1..30).map { uri(it) }
        val intent = Intent(Intent.ACTION_SEND_MULTIPLE).apply { clipData = clipOf(*uris.toTypedArray()) }
        assertEquals(ImportActivity.MAX_BATCH, ImportActivity.urisFrom(intent).size)
    }

    @Test
    fun clipItemsWithoutAUriAreSkipped() {
        val clip = ClipData.newPlainText("label", "some text").apply { addItem(ClipData.Item(uri(11))) }
        val intent = Intent(Intent.ACTION_SEND).apply { clipData = clip }
        assertEquals(listOf(uri(11)), ImportActivity.urisFrom(intent))
    }

    @Test
    fun aUriLessClipItemDoesNotDiscardTheValidOnesAroundIt() {
        // Per-item resilience: one unusable entry skips itself, it does not poison the batch.
        val clip = ClipData.newRawUri("books", uri(12)).apply {
            addItem(ClipData.Item("interleaved text"))
            addItem(ClipData.Item(uri(13)))
            addItem(ClipData.Item("more text"))
            addItem(ClipData.Item(uri(14)))
        }
        val intent = Intent(Intent.ACTION_SEND_MULTIPLE).apply { clipData = clip }
        assertEquals(listOf(uri(12), uri(13), uri(14)), ImportActivity.urisFrom(intent))
    }

    @Test
    fun sendMultiple_withAMixedTypeListKeepsOnlyTheUris() {
        // A sender may put other Parcelables alongside the streams; those are dropped,
        // not fatal, and the behaviour must not depend on the API level's IntentCompat
        // implementation.
        val payload = arrayListOf<android.os.Parcelable>(uri(15), Intent("noise"), uri(16))
        val intent = Intent(Intent.ACTION_SEND_MULTIPLE)
            .putParcelableArrayListExtra(Intent.EXTRA_STREAM, payload)
        assertEquals(listOf(uri(15), uri(16)), ImportActivity.urisFrom(intent))
    }

    @Test
    fun unknownActionAndNullIntentReturnEmpty() {
        assertEquals(emptyList<Uri>(), ImportActivity.urisFrom(null))
        assertEquals(emptyList<Uri>(), ImportActivity.urisFrom(Intent(Intent.ACTION_MAIN, uri(12))))
        assertEquals(emptyList<Uri>(), ImportActivity.urisFrom(Intent()))
    }

    @Test
    fun maxBatchIsTwenty() {
        assertEquals(20, ImportActivity.MAX_BATCH)
        assertTrue(ImportActivity.MAX_BATCH > 0)
        // The scan bound must leave real headroom over the collection bound, or a mixed
        // share would lose books.
        assertTrue(ImportActivity.MAX_SCANNED_ITEMS > ImportActivity.MAX_BATCH)
    }

    @Test
    fun aSparseListPayloadIsBoundedByTheScanCap() {
        // MAX_BATCH alone cannot bound this: none of the noise is a Uri, so a naive
        // extractor would walk every entry a hostile sender cared to send.
        val payload = ArrayList<android.os.Parcelable>()
        repeat(ImportActivity.MAX_SCANNED_ITEMS + 5) { payload.add(Intent("noise")) }
        payload.add(uri(19))
        val intent = Intent(Intent.ACTION_SEND_MULTIPLE)
            .putParcelableArrayListExtra(Intent.EXTRA_STREAM, payload)
        assertEquals(emptyList<Uri>(), ImportActivity.urisFrom(intent))
    }

    @Test
    fun aUriJustInsideTheScanCapIsStillFound() {
        val payload = ArrayList<android.os.Parcelable>()
        repeat(ImportActivity.MAX_SCANNED_ITEMS - 1) { payload.add(Intent("noise")) }
        payload.add(uri(20))
        val intent = Intent(Intent.ACTION_SEND_MULTIPLE)
            .putParcelableArrayListExtra(Intent.EXTRA_STREAM, payload)
        assertEquals(listOf(uri(20)), ImportActivity.urisFrom(intent))
    }

    @Test
    fun aSparseClipDataPayloadIsBoundedByTheScanCap() {
        val clip = ClipData.newPlainText("label", "text 0")
        repeat(ImportActivity.MAX_SCANNED_ITEMS + 5) { clip.addItem(ClipData.Item("text")) }
        clip.addItem(ClipData.Item(uri(21)))
        val intent = Intent(Intent.ACTION_SEND).apply { clipData = clip }
        assertEquals(emptyList<Uri>(), ImportActivity.urisFrom(intent))
    }
}
