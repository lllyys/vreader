package com.vreader.app.reader

import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Feature #156 WI-2 — the effects of `publisherStyles = false` that go **beyond alignment**, each measured
 * as a with-flag / without-flag pair of computed styles. This is the honest accounting of the change's
 * blast radius: setting the flag switches ReadiumCSS from "respect the publisher" to "apply the reader's
 * typography", and that is a visible change to a book's own paragraph alignment, heading sizes and
 * paragraph font sizes — not only to justification.
 *
 * | | Effect | Verified here |
 * |---|---|---|
 * | **E1b** | a publisher's own `text-align` on `<p>`/`<li>` is overridden (`text-align: inherit !important`), and `text-align-last` forced to `auto`; `blockquote`/`figcaption` prose keeps inheriting the publisher's | `center_ta`, `lastjust_tal`, `quote_ta` |
 * | **E1c** | the alignment rule targets `:root`, so **headings** (and anything else without its own `text-align`) inherit justification too | `h1_ta` |
 * | **E3** | the advanced type scale (1.2ⁿ rem) replaces publisher heading sizes | `h1_fs`, `h2_fs` |
 * | **E4** | paragraph font sizes flatten to exactly `1rem` | `tiny_fs` |
 *
 * **Why a synthetic fixture** (AGENTS.md exception — *the test needs a deterministic tiny structure a real
 * book can't give cheaply*): every one of these needs a book that sets the property **on the overridden
 * element itself**. An exhaustive scan of the real Latin EPUB's markup and CSS finds `text-align` on
 * exactly two container classes and on no `p`, `li` or `blockquote`, and it sets no `text-align-last` at
 * all — against which the assertions would be vacuous (`auto` is the CSS initial value). E1/E2/E5 and the
 * CJK characterisation are all measured on the **real** books in [EpubJustifyConnectedTest].
 *
 * Run ONE class per connected invocation (MEMORY #127/#129/#133).
 */
@RunWith(AndroidJUnit4::class)
class EpubPublisherStylesEffectsConnectedTest : ReaderSettingsIsolatedTest() {

    private companion object {
        const val TAG = "WI2-JUSTIFY"
        val START_ALIGNMENTS = setOf("start", "left")

        /** Reads the alignment/size of the specific elements the synthetic fixture was built to exercise. */
        const val TARGETED_JS = """
            (function(){
              try{
                var o={rootStyle:document.documentElement.getAttribute('style')||'',
                       rootFontSize:getComputedStyle(document.documentElement).fontSize,
                       bodyTextAlign:getComputedStyle(document.body).textAlign};
                var sels={plain:'p.plain',center:'p.pub-center',quoteBox:'blockquote.pub-right',
                          quote:'blockquote.pub-right p',lastjust:'p.pub-lastjustify',
                          h1:'h1',h2:'h2',h3:'h3',h4:'h4',h5:'h5',h6:'h6',tiny:'p.tiny',
                          small:'small',sub:'sub',sup:'sup'};
                for(var k in sels){
                  var e=document.querySelector(sels[k]); if(!e) continue;
                  var c=getComputedStyle(e); o[k+'_ta']=c.textAlign; o[k+'_fs']=c.fontSize;
                  o[k+'_tal']=c.textAlignLast||c.webkitTextAlignLast||'';
                }
                return JSON.stringify(o);
              }catch(e){return JSON.stringify({error:String(e)});}
            })()
        """
    }

    @Test
    fun publisherStylesFalse_overridesParagraphAlignment_keepsBlockquote_andEngagesTypeScale() {
        val book = EpubFixtures.importBytes(
            "wi2-publisher-aligned-${System.nanoTime()}.epub",
            EpubFixtures.publisherAlignedEpubBytes(),
        )
        val settings = currentSettings()
        launchReader(book).use { scenario ->
            val probe = EpubDomProbe(scenario, TAG)
            probe.awaitNavigator()
            // Production open-time state — the app's own initialPrefs, nothing submitted by the test.
            probe.advanceToProse("synthetic:publisher-aligned") {
                advancedOn(it) && hasDecl(it, "--USER__textAlign: justify")
            }
            val withFlag = requireNotNull(probe.evalJson(TARGETED_JS)) { "targeted probe returned nothing" }
            assertTrue("the with-flag reading must be under the advanced gate", advancedOn(withFlag))

            probe.submit(legacyPreferences(settings))
            probe.settled("synthetic: pre-#156 mapping live (advanced gate OFF)") { !advancedOn(it) }
            val legacy = requireNotNull(probe.evalJson(TARGETED_JS)) { "targeted probe returned nothing" }
            assertTrue("the control reading must NOT be under the advanced gate", !advancedOn(legacy))

            Log.i(TAG, "E1b/E1c/E3/E4-SUMMARY withFlag=$withFlag legacy=$legacy")

            // E1b — a paragraph the PUBLISHER centred is forced to the reader's alignment, while prose
            // inside a blockquote keeps inheriting the publisher's (blockquote is not in the override list,
            // so it keeps its own alignment and its paragraphs inherit that instead of the root's).
            assertEquals("control: the publisher's centred <p> must start out centred", "center", legacy.optString("center_ta"))
            assertEquals(
                "E1b: under the advanced gate ReadiumCSS forces `text-align: inherit !important` on <p>, so a " +
                    "publisher-centred paragraph is overridden to the reader's alignment. A real user-visible " +
                    "effect of publisherStyles=false beyond 'prose justifies'.",
                "justify", withFlag.optString("center_ta"),
            )
            assertEquals("control: the publisher's right-aligned blockquote", "right", legacy.optString("quote_ta"))
            assertEquals(
                "E1b bound: blockquote prose must KEEP the publisher's alignment",
                "right", withFlag.optString("quote_ta"),
            )
            assertEquals("plain prose justifies under the flag", "justify", withFlag.optString("plain_ta"))
            assertTrue(
                "control: plain prose must not already justify (was '${legacy.optString("plain_ta")}')",
                legacy.optString("plain_ta") in START_ALIGNMENTS,
            )

            // E1b, second half — `text-align-last: auto !important`, i.e. no stretched final line even for a
            // book that asked for one. Discriminating ONLY against a fixture that sets it; elsewhere both
            // states read `auto` (the CSS initial value) and the assertion would be vacuous.
            assertEquals(
                "control: the publisher asked for a justified LAST line",
                "justify", legacy.optString("lastjust_tal"),
            )
            assertEquals(
                "E1b: the override forces text-align-last back to auto",
                "auto", withFlag.optString("lastjust_tal"),
            )

            // E1c — broader than "body prose justifies": the rule that applies our alignment targets `:root`,
            // so every element without its own `text-align` inherits it, headings included. A one-line
            // heading is unaffected (a block's last line is never stretched); a wrapping one is justified.
            // ReadiumCSS's own designed behaviour, and what iOS #95 ships through the same engine — pinned
            // here so it is an executable known property rather than something a user discovers.
            assertTrue(
                "control: a heading must not already be justified (was '${legacy.optString("h1_ta")}')",
                legacy.optString("h1_ta") in START_ALIGNMENTS,
            )
            assertEquals(
                "E1c characterisation: headings inherit the reader's justification from :root. A start/left " +
                    "reading here means ReadiumCSS narrowed the rule and the effect note must be revisited.",
                "justify", withFlag.optString("h1_ta"),
            )

            val root = requireNotNull(pxOrNull(withFlag.optString("rootFontSize"))) { "root font size unreadable" }
            val rootLegacy = requireNotNull(pxOrNull(legacy.optString("rootFontSize"))) { "root font size unreadable" }
            assertEquals("the root font size must not move between the two states", rootLegacy, root, 0.01)

            // E3 — the advanced type scale replaces the publisher's sizes across the WHOLE selector list the
            // block names (h1-h3 at 1.2^n rem, h4-h6 flat 1rem, small/sub/sup their own values), not just
            // the two headings the plan's E3 row happened to quote.
            // Every element the advanced block names, each with the publisher size the fixture gives it and
            // the EXACT size the block replaces it with. No entry may be optional: an expectation that can
            // be skipped is an assertion that cannot fail, which is how `small` slipped through round 1.
            val typeScale = listOf(
                // key, publisher em, expected px under the flag
                Triple("h1", 3.0, 1.728 * root), // 1.2^3 rem
                Triple("h2", 2.0, 1.44 * root), //  1.2^2 rem
                Triple("h3", 1.9, 1.2 * root), //   1.2^1 rem
                Triple("h4", 1.8, root), //         the h4-h6 rule: a flat 1rem
                Triple("h5", 1.75, root),
                Triple("h6", 1.72, root),
                // `small` computes `smaller`, Chromium's relative step down from the 1rem parent (5/6 rem);
                // sub/sup a flat 67.5%. Both replace the publisher's inflated em sizes.
                Triple("small", 1.7, (5.0 / 6.0) * root),
                Triple("sub", 1.6, 0.675 * root),
                Triple("sup", 1.55, 0.675 * root),
            )
            for ((key, em, expected) in typeScale) {
                val legacyPx = requireNotNull(pxOrNull(legacy.optString("${key}_fs"))) { "$key unreadable in control" }
                val flagPx = requireNotNull(pxOrNull(withFlag.optString("${key}_fs"))) { "$key unreadable" }
                // Tolerances are deliberately tight (±1% of root ≈ 0.16px at 16px). At ±3% the h1
                // assertion could not tell the block's computed 1.2^3 rem from its 1.75rem fallback
                // declaration, and `small` could not tell 5/6 rem from a 13px keyword-table result —
                // i.e. the assertion would name a value it cannot actually discriminate.
                assertEquals(
                    "control: the publisher's $key must render at its own ${em}em before the change",
                    em * root, legacyPx, root * 0.01,
                )
                assertTrue(
                    "E3: the advanced type scale must shrink $key from the publisher's ${em}em " +
                        "(${legacyPx}px -> ${flagPx}px)",
                    flagPx < legacyPx - 0.5,
                )
                assertEquals(
                    "E3: $key must land on the advanced block's own size, not merely somewhere smaller",
                    expected, flagPx, root * 0.01,
                )
            }

            // E4 — paragraph font sizes flatten to 1rem, overriding a publisher's smaller size.
            val tiny = requireNotNull(pxOrNull(withFlag.optString("tiny_fs"))) { "tiny <p> unreadable" }
            val tinyLegacy = requireNotNull(pxOrNull(legacy.optString("tiny_fs"))) { "tiny <p> unreadable" }
            assertEquals("control: the publisher's small <p> is 0.75em", 0.75 * root, tinyLegacy, root * 0.05)
            assertEquals("E4: a <p> font size flattens to exactly 1rem under the advanced gate", root, tiny, root * 0.02)
        }
    }
}
