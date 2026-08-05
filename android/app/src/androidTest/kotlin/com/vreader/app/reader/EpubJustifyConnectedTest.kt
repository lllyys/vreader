package com.vreader.app.reader

import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.vreader.app.reader.settings.ReaderSettings
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #156 WI-2 — EPUB justification **and** the fix for bug #367 / GH #2074, verified where it is
 * real: the computed style of the live Readium DOM, on the **real** books.
 *
 * Nothing here asserts a preference object. `assertEquals(JUSTIFY, prefs.textAlign)` and "the navigator
 * accepted the value" both pass with zero pixels moved — that is exactly how #129's line-spacing slider
 * shipped `VERIFIED` while being inert. And nothing decisive is asserted on `<p>`: a publisher's own CSS
 * can already compute `justify` there (WI-0 measured precisely that on the CJK book), so a green `<p>`
 * assertion can be green for entirely the wrong reason. **`body` is the discriminating element** — only
 * ReadiumCSS's override selector names it.
 *
 * Every claim is a with-flag / without-flag **pair**, because a single-state reading proves nothing: the
 * "without" arm submits [legacyPreferences], a field-for-field reconstruction of the pre-#156 mapping, so
 * the control is literally what production did yesterday.
 *
 *  • **E1** body prose justifies, at open and after a live settings change (AC-4) — plus **E5**, ReadiumCSS
 *    auto-enabling hyphenation under justify.
 *  • **E2** line spacing starts working — **bug #367 / GH #2074**, driven through the production slider.
 *  • **CJK**: the alignment half cannot reach a `zh`/`ja`/`ko` publication, while the line-height half does.
 *
 * The remaining effects of `publisherStyles = false` (a publisher's own paragraph alignment, heading type
 * scale, paragraph font-size flattening) need a book that sets those properties on the overridden elements
 * themselves, which no real fixture here does — [EpubPublisherStylesEffectsConnectedTest].
 *
 * Run ONE class per connected invocation, and re-push the real EPUBs first — the connected task wipes the
 * app's external files dir at run end (MEMORY #127/#129/#133).
 */
@RunWith(AndroidJUnit4::class)
class EpubJustifyConnectedTest : ReaderSettingsIsolatedTest() {

    private companion object {
        const val TAG = "WI2-JUSTIFY"
        val START_ALIGNMENTS = setOf("start", "left")
    }

    // ------------------------------------------------------------------ E1 + E5 (real Latin book)

    /**
     * **AC-4 / E1 / E5.** Opening the book through the production path — no submission by the test — must
     * compute `justify` on `body`; submitting the pre-#156 mapping must NOT; re-submitting the production
     * mapping (what `observeDisplaySettings` does on every settings change) must restore it.
     *
     * The middle arm is the load-bearing one: it is what makes "the flag is required, not decorative" a
     * measurement rather than a claim.
     */
    @Test
    fun enEpub_productionOpen_justifies_whileTheLegacyMappingDoesNot() {
        val book = EpubFixtures.importRealEpub(EpubFixtures.EN_FILE, EpubFixtures.EN_BYTES)
        val settings = currentSettings()
        launchReader(book).use { scenario ->
            val probe = EpubDomProbe(scenario, TAG)
            probe.awaitNavigator()

            // Production open-time state — the reader's own initialPrefs, nothing submitted by the test.
            val production = probe.advanceToProse("real:The Half Second(en)") {
                advancedOn(it) && hasDecl(it, "--USER__textAlign: justify") &&
                    it.optInt("censusSampled") >= 3
            }
            probe.logState("E1", "en", "production-open", production)

            probe.submit(legacyPreferences(settings))
            val legacy = probe.settled("en: pre-#156 mapping live (advanced gate OFF)") { !advancedOn(it) }
            probe.logState("E1", "en", "legacy-control(pre-#156 mapping)", legacy)

            probe.submit(settings.toEpubPreferences())
            val relive = probe.settled("en: production mapping re-submitted (advanced gate ON)") {
                advancedOn(it) && hasDecl(it, "--USER__textAlign: justify")
            }
            probe.logState("E1", "en", "production-live-resubmit", relive)

            val states = listOf(production, legacy, relive)
            Log.i(
                TAG,
                "E1-SUMMARY body[open=${production.optString("bodyTextAlign")} " +
                    "legacy=${legacy.optString("bodyTextAlign")} relive=${relive.optString("bodyTextAlign")}] " +
                    "hyphens[open=${production.optString("bodyHyphens")} legacy=${legacy.optString("bodyHyphens")}] " +
                    "census[open=${censusOf(production)} legacy=${censusOf(legacy)}]",
            )

            assertTrue("all three readings must be of the same resource + element", sameContent(states))
            assertTrue(
                "the Latin book must resolve the DEFAULT ReadiumCSS, not the CJK one (the contrast that " +
                    "makes the zh-CN result meaningful) — sheets=${production.optString("sheets")}",
                production.optString("sheets").contains("readium-css/ReadiumCSS-after.css") &&
                    !production.optString("sheets").contains("cjk-horizontal"),
            )
            assertEquals(
                "publisherStyles=false must not cause a DIFFERENT set of ReadiumCSS stylesheets to be " +
                    "injected — otherwise the effect set is not bounded to the advanced-gated rules",
                legacy.optString("sheets"),
                production.optString("sheets"),
            )

            // E1 — the pair.
            assertEquals(
                "AC-4: opening the book through the production path must compute text-align: justify on body",
                "justify", production.optString("bodyTextAlign"),
            )
            assertTrue(
                "the pre-#156 mapping must NOT justify (was '${legacy.optString("bodyTextAlign")}') — if it " +
                    "did, this test would prove nothing about the change",
                legacy.optString("bodyTextAlign") in START_ALIGNMENTS,
            )
            assertEquals(
                "AC-4: a live re-submission (the observeDisplaySettings path) must justify too",
                "justify", relive.optString("bodyTextAlign"),
            )

            // E1 on the prose itself: every substantial non-blockquote/figcaption <p> justifies.
            val census = censusOf(production)
            assertTrue("the census must have sampled real paragraphs", census.values.sum() >= 3)
            assertEquals(
                "every sampled prose <p> must compute justify under the production preferences — census=$census",
                setOf("justify"), census.keys,
            )
            assertEquals(
                "control: the same paragraphs must not already be justified — census=${censusOf(legacy)}",
                setOf<String>(), censusOf(legacy).keys - START_ALIGNMENTS,
            )

            // NOTE — deliberately NOT asserted here: `bodyTextAlignLast == "auto"`. It reads `auto` in BOTH
            // states, because `auto` is also the CSS initial value, so the assertion would pass whether or
            // not the override rule fired. The discriminating measurement for that rule needs a book that
            // sets `text-align-last` itself — EpubPublisherStylesEffectsConnectedTest.

            // E5 — ReadiumCSS auto-enables hyphenation under justify (matches the design's hyphens:'auto').
            assertEquals(
                "E5: hyphens must compute auto on body under justify",
                "auto", production.optString("bodyHyphens"),
            )
            assertTrue(
                "E5 control: hyphens must NOT already be auto under the pre-#156 mapping " +
                    "(was '${legacy.optString("bodyHyphens")}')",
                legacy.optString("bodyHyphens") != "auto",
            )
        }
    }

    // ------------------------------------------------------------------ E2 / AC-6 (bug #367)

    /**
     * **Bug #367 / GH #2074, AC-6.** The regression test: move the Display sheet's line-spacing slider
     * through the production store and require the **computed** `line-height` to change. WI-0 measured
     * 24.2109px → 24.2109px across exactly this action before the fix.
     *
     * It asserts the ratio, not merely "different": a value that changed by the wrong amount would mean the
     * slider is connected to something other than the line height the user asked for.
     */
    @Test
    fun enEpub_lineSpacingSlider_movesComputedLineHeight_bug367() {
        val book = EpubFixtures.importRealEpub(EpubFixtures.EN_FILE, EpubFixtures.EN_BYTES)
        val store = EpubFixtures.app.container.readerSettingsStore
        runBlocking { store.setLineSpacing(ReaderSettings.DEFAULT_LINE_SPACING) }
        launchReader(book).use { scenario ->
            val probe = EpubDomProbe(scenario, TAG)
            probe.awaitNavigator()

            val before = probe.advanceToProse("real:The Half Second(en)") {
                advancedOn(it) && hasDecl(it, "--USER__lineHeight: 1.5")
            }
            probe.logState("E2", "en", "lineSpacing=1.5 (production)", before)

            // The real user action: drag the line-spacing slider to its maximum.
            runBlocking { store.setLineSpacing(ReaderSettings.MAX_LINE_SPACING) }
            val after = probe.settled("--USER__lineHeight: 2.0 live, advanced gate ON") {
                advancedOn(it) && hasDecl(it, "--USER__lineHeight: 2.0")
            }
            probe.logState("E2", "en", "lineSpacing=2.0 (production)", after)

            val b = pxOrNull(before.optString("bodyLineHeight"))
            val a = pxOrNull(after.optString("bodyLineHeight"))
            val bFont = pxOrNull(before.optString("bodyFontSize"))
            val aFont = pxOrNull(after.optString("bodyFontSize"))
            Log.i(
                TAG,
                "E2-SUMMARY bug367 bodyLineHeight[1.5=$b 2.0=$a] bodyFontSize[$bFont -> $aFont] " +
                    "elem[${before.optString("lineHeight")} -> ${after.optString("lineHeight")}]",
            )

            assertTrue("the readings must be of the same resource + element", sameContent(listOf(before, after)))
            assertNotNull("computed line-height at 1.5 must be a real px length", b)
            assertNotNull("computed line-height at 2.0 must be a real px length", a)
            assertNotNull("font size must be readable, since line-height is asserted relative to it", bFont)
            assertEquals("the font size must not have moved — it would confound the ratio", bFont!!, aFont!!, 0.01)
            assertTrue(
                "bug #367: moving the line-spacing slider must CHANGE the computed line-height " +
                    "($b -> $a). Unchanged means --USER__lineHeight is being emitted and ignored again.",
                a!! > b!! + 0.5,
            )
            assertEquals(
                "the computed line-height must be the requested multiple of the font size " +
                    "(2.0 x $bFont), not merely 'some other number'",
                2.0 * bFont, a, 0.6,
            )
            assertEquals("and the baseline must be 1.5 x the font size", 1.5 * bFont, b, 0.6)
        }
    }

    // ------------------------------------------------------------------ CJK

    /**
     * **AC-5 (EPUB leg), characterisation.** `cjk-horizontal/ReadiumCSS-after.css` contains no
     * `--USER__textAlign` rule, so the alignment half of this feature cannot reach a `zh`/`ja`/`ko`
     * publication — WI-0 measured it, and this pins it, so a future Readium upgrade that starts honouring
     * `text-align` for CJK fails here rather than rotting in a prose prediction (feature #174 tracks the
     * follow-up).
     *
     * It is NOT a null result overall: the CJK stylesheet *does* carry the `--USER__lineHeight` rule and the
     * flag-only type-scale rules, so `publisherStyles = false` fixes bug #367 for CJK books too. That half
     * is asserted here.
     */
    @Test
    fun zhEpub_cjkKeepsStartAlignment_butLineHeightNowApplies() {
        val book = EpubFixtures.importRealEpub(EpubFixtures.ZH_FILE, EpubFixtures.ZH_BYTES)
        val store = EpubFixtures.app.container.readerSettingsStore
        runBlocking { store.setLineSpacing(ReaderSettings.DEFAULT_LINE_SPACING) }
        launchReader(book).use { scenario ->
            val probe = EpubDomProbe(scenario, TAG)
            probe.awaitNavigator()
            val before = probe.advanceToProse("real:道诡异仙(zh-CN)") {
                advancedOn(it) && hasDecl(it, "--USER__lineHeight: 1.5")
            }
            probe.logState("CJK", "zh", "production lineSpacing=1.5", before)

            runBlocking { store.setLineSpacing(ReaderSettings.MAX_LINE_SPACING) }
            val after = probe.settled("zh: --USER__lineHeight: 2.0 live, advanced gate ON") {
                advancedOn(it) && hasDecl(it, "--USER__lineHeight: 2.0")
            }
            probe.logState("CJK", "zh", "production lineSpacing=2.0", after)

            Log.i(
                TAG,
                "CJK-SUMMARY lang=${before.optString("lang")} sheets=${before.optString("sheets")} " +
                    "bodyTextAlign=${before.optString("bodyTextAlign")} pTextAlign=${before.optString("textAlign")} " +
                    "bodyLineHeight[1.5=${before.optString("bodyLineHeight")} 2.0=${after.optString("bodyLineHeight")}]",
            )

            assertTrue(
                "the publication must declare a zh language (was '${before.optString("lang")}')",
                before.optString("lang").startsWith("zh"),
            )
            assertTrue(
                "Readium must have resolved the cjk-horizontal stylesheet — sheets=${before.optString("sheets")}",
                before.optString("sheets").contains("cjk-horizontal/ReadiumCSS-after.css"),
            )
            assertTrue(
                "characterisation: body must stay start/left on a CJK publication even under the advanced " +
                    "gate (was '${before.optString("bodyTextAlign")}') — cjk-horizontal has no USER__textAlign " +
                    "rule. A 'justify' here means the CJK EPUB prediction is REFUTED and feature #174's EPUB " +
                    "half can be closed.",
                before.optString("bodyTextAlign") in START_ALIGNMENTS,
            )

            val b = requireNotNull(pxOrNull(before.optString("bodyLineHeight"))) { "line-height at 1.5 unreadable" }
            val a = requireNotNull(pxOrNull(after.optString("bodyLineHeight"))) { "line-height at 2.0 unreadable" }
            val font = requireNotNull(pxOrNull(before.optString("bodyFontSize"))) { "font size unreadable" }
            assertTrue("the readings must be of the same resource + element", sameContent(listOf(before, after)))
            assertTrue(
                "bug #367 is fixed for CJK books too — cjk-horizontal DOES carry the --USER__lineHeight " +
                    "rule, so the slider must move the computed line-height ($b -> $a)",
                a > b + 0.5,
            )
            assertEquals("and to the requested multiple of the font size", 2.0 * font, a, 0.6)
        }
    }
}
