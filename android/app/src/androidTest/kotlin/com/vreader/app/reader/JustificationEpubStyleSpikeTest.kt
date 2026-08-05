package com.vreader.app.reader

import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.navigator.preferences.TextAlign as ReadiumTextAlign

/**
 * Feature #156 WI-0 — the **measurement spike** for the EPUB (Readium / Chromium) engine, kept as a live
 * characterisation of the *mechanism* WI-2 then shipped. Every number is read out of the live DOM with
 * `getComputedStyle`, never off an `EpubPreferences` object (see [EpubDomProbe] for why that distinction
 * decides whether these tests mean anything).
 *
 *  • **M3** — computed `text-align` on the real `en` and `zh-CN` EPUBs under three preference states:
 *    no alignment preference at all, `textAlign = JUSTIFY` alone, and `textAlign = JUSTIFY` +
 *    `publisherStyles = false`. The `en` book computing `justify` ONLY in the third state is the proof
 *    that the flag — not the alignment preference — is what makes ReadiumCSS apply anything.
 *  • **M4** — the ROOT CAUSE of bug #367 / GH #2074: with `publisherStyles` unset, a line-height change is
 *    emitted as `--USER__lineHeight` and no rule consumes it. That is the defect WI-2 fixed.
 *
 * **Re-based by WI-2, deliberately.** The first two states used to be read straight off the app's open-time
 * preferences, because production never set `publisherStyles`. Production now does (that IS #156 WI-2), so
 * those baselines are reconstructed here by explicit submission. Without this the class would have kept
 * asserting a production behaviour that no longer exists — a false claim that happens to be green. The
 * *production* verification (justify at open, and the slider actually moving line-height) lives in
 * [EpubJustifyConnectedTest]; this class stays on the mechanism.
 *
 * Run ONE class per connected invocation; re-push the real EPUBs first (MEMORY #127/#129/#133).
 */
@RunWith(AndroidJUnit4::class)
class JustificationEpubStyleSpikeTest : ReaderSettingsIsolatedTest() {

    private companion object {
        const val TAG = "WI0-JUSTIFY"

        /** Everything the production mapper sets EXCEPT the #156 pair — i.e. the pre-#156 preference set. */
        @OptIn(ExperimentalReadiumApi::class)
        fun withoutAlignment(lineHeight: Double = 1.5) = EpubPreferences(fontSize = 1.0, lineHeight = lineHeight)
    }

    // ---------------------------------------------------------------- M3

    /** The computed `text-align` of the prose element and of `body`, under one preference state. */
    private data class AlignReading(val element: String, val body: String, val tag: String)

    /** The three readings plus the invariants that prove all three measured the SAME content. */
    private data class AlignRun(
        val noAlignmentPref: AlignReading,
        val justifyOnly: AlignReading,
        val withFlag: AlignReading,
        val lang: String,
        val sheets: String,
        val sameContentThroughout: Boolean,
    )

    @OptIn(ExperimentalReadiumApi::class)
    private fun measureTextAlign(file: String, bytes: Long, label: String): AlignRun {
        val book = EpubFixtures.importRealEpub(file, bytes)
        var out: AlignRun? = null
        launchReader(book).use { scenario ->
            val probe = EpubDomProbe(scenario, TAG)
            probe.awaitNavigator()

            // State 1 — no alignment preference and no advanced gate. Reconstructed by submission, since
            // production (post-#156) opens WITH both.
            probe.advanceToProse(label)
            probe.submit(withoutAlignment())
            val base = probe.settled("$label: no alignment preference, advanced gate OFF") {
                !advancedOn(it) && !hasDecl(it, "--USER__textAlign") &&
                    it.optInt("textLen") >= EpubDomProbe.MIN_PROSE_CHARS
            }
            probe.logState("M3", label, "no-alignment-preference", base)

            // Each submission is followed by a probe that REQUIRES the requested variables to be live in the
            // DOM, so a reading can never be of the previous state.
            probe.submit(withoutAlignment() + EpubPreferences(textAlign = ReadiumTextAlign.JUSTIFY))
            val justifyOnly = probe.settled("$label: --USER__textAlign live, advanced gate OFF") {
                hasDecl(it, "--USER__textAlign: justify") && !advancedOn(it)
            }
            probe.logState("M3", label, "textAlign=JUSTIFY,publisherStyles-unset", justifyOnly)

            probe.submit(
                withoutAlignment() +
                    EpubPreferences(textAlign = ReadiumTextAlign.JUSTIFY, publisherStyles = false),
            )
            val withFlag = probe.settled("$label: --USER__textAlign live, advanced gate ON") {
                hasDecl(it, "--USER__textAlign: justify") && advancedOn(it)
            }
            probe.logState("M3", label, "textAlign=JUSTIFY,publisherStyles=false", withFlag)

            fun read(p: JSONObject) =
                AlignReading(p.optString("textAlign"), p.optString("bodyTextAlign"), p.optString("tag"))
            out = AlignRun(
                noAlignmentPref = read(base), justifyOnly = read(justifyOnly), withFlag = read(withFlag),
                lang = base.optString("lang"),
                sheets = base.optString("sheets"),
                // All three readings must come from the same resource AND the same element, or a "nothing
                // changed" verdict could just be two different paragraphs.
                sameContentThroughout = sameContent(listOf(base, justifyOnly, withFlag)),
            )
        }
        return out!!
    }

    /**
     * **M3 (Latin `en`)** — the proof that `textAlign = JUSTIFY` is INERT while `publisherStyles` is unset,
     * and takes effect only once the flag turns `readium-advanced-on` on. This pair is what makes WI-2's
     * two properties inseparable (plan §7.2).
     */
    @Test fun m3_enEpub_justifyRequiresPublisherStylesFalse() {
        val run = measureTextAlign(EpubFixtures.EN_FILE, EpubFixtures.EN_BYTES, "real:The Half Second(en)")
        Log.i(TAG, "M3-SUMMARY book=en $run")
        assertTrue("M3/en: all three readings must be of the same resource + element", run.sameContentThroughout)
        assertEquals("M3/en: the Latin book must declare English", "en", run.lang)
        assertTrue(
            "M3/en: the Latin book must resolve the DEFAULT ReadiumCSS, not the CJK one (the contrast that " +
                "makes the zh-CN result meaningful) — sheets=${run.sheets}",
            run.sheets.contains("readium-css/ReadiumCSS-after.css") && !run.sheets.contains("cjk-horizontal"),
        )
        assertEquals(
            "M3/en: computed text-align on body with publisherStyles=false must be justify " +
                "(body is named directly in ReadiumCSS's override selector)",
            "justify", run.withFlag.body,
        )
        // Positive, not merely "not justify": the un-gated states must be a real start/left value, so an
        // empty or error reading cannot masquerade as "the override did not apply".
        assertTrue(
            "M3/en: WITHOUT the advanced gate the computed body text-align must be a real start/left " +
                "value (was '${run.justifyOnly.body}') — the variable is emitted but no rule consumes it",
            run.justifyOnly.body in setOf("start", "left"),
        )
        assertTrue(
            "M3/en: with no alignment preference at all it must likewise be start/left " +
                "(was '${run.noAlignmentPref.body}')",
            run.noAlignmentPref.body in setOf("start", "left"),
        )
    }

    /**
     * **M3 (CJK `zh-CN`)** — `cjk-horizontal/ReadiumCSS-after.css` contains no `--USER__textAlign` rule, and
     * the publication declares `zh-CN` so Readium selects that stylesheet. Characterisation: it PINS the
     * measured result so a future Readium upgrade that starts honouring `text-align` for CJK fails here and
     * forces the prediction to be revisited.
     *
     * **`body` is the discriminating element here, and the reason is a finding in itself.** The measured run
     * showed this book's `<p>` computing `text-align: justify` in ALL THREE states — including before any
     * submission. That is the PUBLISHER's own stylesheets, not our preference: the book ships justified.
     * Asserting on `<p>` would have "passed" for entirely the wrong reason and looked like #156 working on
     * CJK. `body` is only ever styled by ReadiumCSS's override selector, so it isolates OUR effect.
     */
    @Test fun m3_zhEpub_cjkStylesheet_characterisation() {
        val run = measureTextAlign(EpubFixtures.ZH_FILE, EpubFixtures.ZH_BYTES, "real:道诡异仙(zh-CN)")
        Log.i(TAG, "M3-SUMMARY book=zh $run")
        // Every precondition of the characterisation is asserted, so the test cannot "pass" by measuring an
        // error object, a stale DOM, the wrong resource, or a non-CJK stylesheet.
        assertTrue("M3/zh: all three readings must be of the same resource + element", run.sameContentThroughout)
        assertTrue("M3/zh: the publication must declare a zh language (was '${run.lang}')", run.lang.startsWith("zh"))
        assertTrue(
            "M3/zh: Readium must have resolved the cjk-horizontal stylesheet — sheets=${run.sheets}",
            run.sheets.contains("cjk-horizontal/ReadiumCSS-after.css"),
        )
        assertTrue(
            "M3/zh characterisation: body computed text-align must stay a real start/left value even WITH " +
                "publisherStyles=false (was '${run.withFlag.body}') — cjk-horizontal has no USER__textAlign " +
                "rule, so our override never applies. A 'justify' here STRIKES the CJK EPUB prediction and " +
                "closes feature #174's EPUB half.",
            run.withFlag.body in setOf("start", "left"),
        )
        assertTrue(
            "M3/zh: body must be start/left in the un-gated states too " +
                "(none='${run.noAlignmentPref.body}', justifyOnly='${run.justifyOnly.body}')",
            run.noAlignmentPref.body in setOf("start", "left") && run.justifyOnly.body in setOf("start", "left"),
        )
    }

    // ---------------------------------------------------------------- M4 (bug #367's root cause)

    /**
     * **M4 — the root cause of bug #367 / GH #2074.** With `publisherStyles` unset, changing the line height
     * moves `--USER__lineHeight` in the `<html>` inline style and leaves the computed `line-height`
     * untouched, because the only rule that reads that variable sits behind `readium-advanced-on`. The same
     * value WITH the flag renders. That is exactly why WI-2's two properties ship together.
     *
     * This drives the states by explicit submission. The *production* regression — the Display sheet's
     * slider moving the computed line height — is
     * [EpubJustifyConnectedTest.enEpub_lineSpacingSlider_movesComputedLineHeight_bug367].
     */
    @OptIn(ExperimentalReadiumApi::class)
    @Test fun m4_lineHeightIsInertWithoutPublisherStyles_bug367RootCause() {
        val book = EpubFixtures.importRealEpub(EpubFixtures.EN_FILE, EpubFixtures.EN_BYTES)
        launchReader(book).use { scenario ->
            val probe = EpubDomProbe(scenario, TAG)
            probe.awaitNavigator()
            probe.advanceToProse("real:The Half Second(en)")

            probe.submit(withoutAlignment(lineHeight = 1.5))
            val before = probe.settled("--USER__lineHeight: 1.5 live, advanced gate OFF") {
                hasDecl(it, "--USER__lineHeight: 1.5") && !advancedOn(it) &&
                    it.optInt("textLen") >= EpubDomProbe.MIN_PROSE_CHARS
            }
            probe.logState("M4", "en", "lineHeight=1.5, publisherStyles unset", before)

            // The probe REQUIRES --USER__lineHeight to actually read 2.0 before it counts, so "the computed
            // value did not change" can never be an artifact of reading before the change landed.
            probe.submit(withoutAlignment(lineHeight = 2.0))
            val after = probe.settled("--USER__lineHeight: 2.0 live, advanced gate OFF") {
                hasDecl(it, "--USER__lineHeight: 2.0") && !advancedOn(it)
            }
            probe.logState("M4", "en", "lineHeight=2.0, publisherStyles unset", after)

            probe.submit(withoutAlignment(lineHeight = 2.0) + EpubPreferences(publisherStyles = false))
            val fixed = probe.settled("--USER__lineHeight: 2.0 live, advanced gate ON") {
                hasDecl(it, "--USER__lineHeight: 2.0") && advancedOn(it)
            }
            probe.logState("M4", "en", "lineHeight=2.0, publisherStyles=false", fixed)

            val bh0 = before.optString("bodyLineHeight")
            val bh1 = after.optString("bodyLineHeight")
            val bh2 = fixed.optString("bodyLineHeight")
            Log.i(
                TAG,
                "M4-SUMMARY bug367 body[1.5=$bh0 2.0_unset=$bh1 2.0_flagOn=$bh2] " +
                    "inert=${bh0 == bh1} flag_fixes_it=${bh2 != bh0}",
            )
            // Guard against a vacuous pass: an empty reading would make every comparison trivially true.
            for ((name, v) in listOf("bh0" to bh0, "bh1" to bh1, "bh2" to bh2)) {
                assertTrue("M4: computed $name must be a real px length, was '$v'", pxOrNull(v) != null)
            }
            assertTrue(
                "M4: the three readings must be of the same resource + element",
                sameContent(listOf(before, after, fixed)),
            )
            assertEquals(
                "M4 / bug #367 root cause: with publisherStyles unset, a line-height change must leave the " +
                    "computed line-height UNCHANGED ($bh0 → $bh1). If these ever differ, the root cause is " +
                    "REFUTED and #367's diagnosis must be revisited.",
                bh0, bh1,
            )
            assertNotEquals(
                "M4: the SAME line height with publisherStyles=false must change the computed body " +
                    "line-height — that is what makes WI-2 the fix for #367",
                bh0, bh2,
            )
        }
    }
}
