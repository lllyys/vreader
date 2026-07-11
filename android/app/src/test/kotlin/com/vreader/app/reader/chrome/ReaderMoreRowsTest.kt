package com.vreader.app.reader.chrome

import com.vreader.app.reader.more.MoreActionId
import com.vreader.app.reader.more.MoreRow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Feature #134 WI-5 — the pure [readerMoreRows] assembler that the reader chrome feeds to the WI-3
 * [com.vreader.app.reader.more.MorePopup]. #134 owns ONLY the Details + Share rows: no TTS / Auto-turn /
 * Bilingual / Export (those belong to other features and are supplied by them, never invented here — the
 * §more-row-ownership contract + the #129 no-dead-control rule). Both are [MoreRow.Action]s wiring their
 * respective callbacks. Robolectric only because constructing the material `ImageVector` icon refs touches
 * Compose's graphics vector; the function itself has no Android/Compose-runtime dependency.
 */
@RunWith(RobolectricTestRunner::class)
class ReaderMoreRowsTest {

    @Test fun assemblesOnlyDetailsAndShare() {
        val rows = readerMoreRows(onDetails = {}, onShare = {})
        assertEquals(listOf(MoreActionId.DETAILS, MoreActionId.SHARE), rows.map { it.id })
    }

    @Test fun bothAreActionRows_withDesignedLabels() {
        val rows = readerMoreRows(onDetails = {}, onShare = {})
        val details = rows.single { it.id == MoreActionId.DETAILS }
        val share = rows.single { it.id == MoreActionId.SHARE }
        assertTrue(details is MoreRow.Action)
        assertTrue(share is MoreRow.Action)
        assertEquals("Book details", details.label)
        assertEquals("Share book", share.label)
    }

    @Test fun detailsActionFiresOnlyOnDetailsTap() {
        var detailed = false
        var shared = false
        val rows = readerMoreRows(onDetails = { detailed = true }, onShare = { shared = true })
        (rows.single { it.id == MoreActionId.DETAILS } as MoreRow.Action).onTap()
        assertTrue(detailed)
        assertFalse(shared)
    }

    @Test fun shareActionFiresOnlyOnShareTap() {
        var detailed = false
        var shared = false
        val rows = readerMoreRows(onDetails = { detailed = true }, onShare = { shared = true })
        (rows.single { it.id == MoreActionId.SHARE } as MoreRow.Action).onTap()
        assertTrue(shared)
        assertFalse(detailed)
    }

    @Test fun noTtsAutoTurnBilingualOrExportRows() {
        val rows = readerMoreRows(onDetails = {}, onShare = {})
        val ids = rows.map { it.id }.toSet()
        assertFalse(ids.contains(MoreActionId.TTS))
        assertFalse(ids.contains(MoreActionId.AUTO_TURN))
        assertFalse(ids.contains(MoreActionId.BILINGUAL))
        // There is deliberately no EXPORT id in MoreActionId — absence is structural.
    }
}
