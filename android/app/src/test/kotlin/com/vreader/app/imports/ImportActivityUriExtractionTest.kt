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
    fun unknownActionAndNullIntentReturnEmpty() {
        assertEquals(emptyList<Uri>(), ImportActivity.urisFrom(null))
        assertEquals(emptyList<Uri>(), ImportActivity.urisFrom(Intent(Intent.ACTION_MAIN, uri(12))))
        assertEquals(emptyList<Uri>(), ImportActivity.urisFrom(Intent()))
    }

    @Test
    fun maxBatchIsTwenty() {
        assertEquals(20, ImportActivity.MAX_BATCH)
        assertTrue(ImportActivity.MAX_BATCH > 0)
    }
}
