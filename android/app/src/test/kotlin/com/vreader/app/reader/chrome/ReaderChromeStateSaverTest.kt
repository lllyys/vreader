package com.vreader.app.reader.chrome

import androidx.compose.runtime.saveable.SaverScope
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Feature #132 WI-5 — the pure-String round-trip contract of [ReaderChromeStateSaver], mirroring #127's
 * `SheetRouteSaver` test. This is the REAL green signal for WI-5 (JVM, no Compose runtime): every
 * (visible, sheet) combination saves to a stable token and restores to the same state, and ANY
 * unrecognized/garbage token restores to the safe fallback (`chromeVisible=false`, `sheet=None`) —
 * never a throw. Edge cases: empty string, wrong separator, unknown sheet name, extra fields.
 */
class ReaderChromeStateSaverTest {

    // A no-op SaverScope — the Saver's `save` never calls `canBeSaved` (it encodes to a String).
    private val scope = SaverScope { true }

    private fun roundTrip(state: ReaderChromeState): ReaderChromeState {
        val token = with(ReaderChromeStateSaver) { scope.save(state) }
        return ReaderChromeStateSaver.restore(token as String)!!
    }

    @Test fun roundTrips_visibleNone() {
        val state = ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None)
        assertEquals(state, roundTrip(state))
    }

    @Test fun roundTrips_hiddenNone() {
        val state = ReaderChromeState(chromeVisible = false, sheet = ReaderSheet.None)
        assertEquals(state, roundTrip(state))
    }

    @Test fun roundTrips_visibleToc() {
        val state = ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.Toc)
        assertEquals(state, roundTrip(state))
    }

    @Test fun roundTrips_visibleNotes() {
        val state = ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.Notes)
        assertEquals(state, roundTrip(state))
    }

    @Test fun roundTrips_hiddenToc() {
        val state = ReaderChromeState(chromeVisible = false, sheet = ReaderSheet.Toc)
        assertEquals(state, roundTrip(state))
    }

    @Test fun roundTrips_visibleDetails() {
        // feature #134 WI-5 — the Book Details route survives process death like Toc/Notes.
        val state = ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.Details)
        assertEquals(state, roundTrip(state))
    }

    @Test fun detailsToken_restoresToDetails() {
        val restored = ReaderChromeStateSaver.restore("true|details")
        assertEquals(ReaderSheet.Details, restored!!.sheet)
    }

    @Test fun garbageToken_restoresToNoneHidden() {
        val fallback = ReaderChromeState(chromeVisible = false, sheet = ReaderSheet.None)
        assertEquals(fallback, ReaderChromeStateSaver.restore("total-garbage"))
    }

    @Test fun emptyToken_restoresToNoneHidden() {
        val fallback = ReaderChromeState(chromeVisible = false, sheet = ReaderSheet.None)
        assertEquals(fallback, ReaderChromeStateSaver.restore(""))
    }

    @Test fun unknownSheetName_restoresToNoneHidden_forVisibleFlag() {
        // A well-formed "visible|<unknown>" token falls back to sheet=None but MUST NOT throw.
        val restored = ReaderChromeStateSaver.restore("true|bookmarks")
        assertEquals(ReaderSheet.None, restored!!.sheet)
    }

    @Test fun wrongSeparator_restoresToNoneHidden() {
        val fallback = ReaderChromeState(chromeVisible = false, sheet = ReaderSheet.None)
        assertEquals(fallback, ReaderChromeStateSaver.restore("true,toc"))
    }

    @Test fun defaultState_isVisibleNone() {
        assertEquals(ReaderChromeState(chromeVisible = true, sheet = ReaderSheet.None), ReaderChromeState())
    }
}
