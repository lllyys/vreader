package vreader.spike

import androidx.fragment.app.testing.FragmentScenario
import androidx.fragment.app.testing.launchFragmentInContainer
import androidx.lifecycle.Lifecycle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import kotlin.math.abs

/**
 * Spike B (#105) WI-3 — CFI / locator anchor-restore + selection probes on the
 * synthetic controlled-offset CJK fixture (mini-cjk.epub, 4 chapters x 24 unique
 * CJK paragraphs, each chapter multi-screen). The Android analogue of the iOS
 * #349/#352 restore saga: does Readium-Kotlin 3.3.0 restore a deep within-chapter
 * scroll position faithfully, and does a saved locator survive the JSON round-trip
 * the backup/restore path depends on? Instrumentation-first, no UI automation.
 *
 * Rubric (plan): reopen lands within the SAME paragraph as saved (sub-paragraph
 * drift is the acceptable Android v1 window); a selection round-trips to the same
 * range. Larger drift -> a recorded engine-hardening obligation (WI-4).
 *
 * MEASURED RESULT (honest, Codex Gate-4): chapter-level restore + Locator JSON
 * round-trip are FAITHFUL; selection round-trips exactly. Fragment-level restore
 * does NOT hit the same-paragraph bar — the target paragraph restores on-screen
 * but ~2 paragraphs (~18% of the viewport) below the top, so the tests gate the
 * engine-blocking invariant (target restored into the top portion of the
 * viewport, not wildly off) and RECORD the exact offset as the #352-class
 * hardening obligation for WI-4; they do not over-claim same-paragraph precision.
 */
@OptIn(ExperimentalReadiumApi::class)
@RunWith(AndroidJUnit4::class)
class AnchorRestoreTest {

    private val instr = InstrumentationRegistry.getInstrumentation()
    private val ctx = instr.targetContext

    private fun mainSync(block: () -> Unit) = instr.runOnMainSync(block)
    private fun settle(ms: Long) { instr.waitForIdleSync(); Thread.sleep(ms) }
    private fun progression(loc: Locator) = loc.locations.progression ?: 0.0

    private fun openFixture(): Publication {
        val file = ReaderOpener.fixtureFile(ctx, "mini-cjk.epub")
        assertTrue("fixture missing at ${file.absolutePath} (push it first)", file.exists())
        return runBlocking { ReaderOpener.open(ctx, file) }
    }

    private fun launchNavigator(pub: Publication): Pair<FragmentScenario<EpubNavigatorFragment>, EpubNavigatorFragment> {
        val factory = EpubNavigatorFactory(pub)
        val scenario = launchFragmentInContainer<EpubNavigatorFragment>(
            factory = factory.createFragmentFactory(
                initialLocator = null,
                initialPreferences = EpubPreferences(scroll = true),
                listener = object : EpubNavigatorFragment.Listener {
                    override fun onExternalLinkActivated(url: org.readium.r2.shared.util.AbsoluteUrl) {}
                },
            ),
            initialState = Lifecycle.State.RESUMED,
        )
        lateinit var nav: EpubNavigatorFragment
        scenario.onFragment { nav = it }
        settle(1200)
        return scenario to nav
    }

    /**
     * Chapter-level locator restore + Locator JSON round-trip fidelity — the
     * position-restore path backup/restore relies on. HONEST SCOPE (Codex Gate-4):
     * Readium's scroll-mode `currentLocator.progression` is resource-coarse (stays
     * ~0 within a resource), so this leg verifies CHAPTER (href) + progression +
     * JSON-round-trip fidelity, NOT sub-chapter precision. Paragraph-level precision
     * is measured separately in paragraphPreciseRestore via a fragment locator.
     */
    @Test
    fun chapterRestoreAndJsonRoundTrip() {
        val pub = openFixture()
        try {
            val spine = pub.readingOrder
            assertEquals("mini-cjk should have 4 chapters", 4, spine.size)
            val (scenario, nav) = launchNavigator(pub)
            try {
                assertTrue("scroll mode did not take effect (paginated fallback?)",
                    nav.settings.value.scroll)

                mainSync { nav.go(pub.locatorFromLink(spine[2])!!, animated = false) }
                settle(600)
                val saved = nav.currentLocator.value
                android.util.Log.i("AnchorRestore", "SAVED href=${saved.href} prog=${progression(saved)} total=${saved.locations.totalProgression}")
                assertEquals("did not land in chapter 3", "OEBPS/chapter3.xhtml", saved.href.toString())

                // Navigate AWAY to chapter 1.
                mainSync { nav.go(pub.locatorFromLink(spine[0])!!, animated = false) }
                settle(500)
                assertNotEquals("navigate-away did not change chapter", saved.href, nav.currentLocator.value.href)

                // RESTORE via the saved locator (the #349/#352 chapter-restore analogue).
                mainSync { nav.go(saved, animated = false) }
                settle(600)
                val restored = nav.currentLocator.value
                android.util.Log.i("AnchorRestore", "RESTORED href=${restored.href} prog=${progression(restored)}")
                assertEquals("restore landed in the wrong chapter", saved.href.toString(), restored.href.toString())
                assertEquals("progression not preserved on restore",
                    progression(saved), progression(restored), 1e-6)

                // Locator JSON round-trip — the save->JSON->restore path backup relies on.
                val json = saved.toJSON().toString()
                val parsed = Locator.fromJSON(JSONObject(json))
                assertTrue("Locator.fromJSON returned null for $json", parsed != null)
                assertEquals("href lost in JSON round-trip", saved.href.toString(), parsed!!.href.toString())
                assertEquals("progression lost in JSON round-trip",
                    saved.locations.progression, parsed.locations.progression)
                assertEquals("totalProgression lost in JSON round-trip",
                    saved.locations.totalProgression, parsed.locations.totalProgression)

                // Navigate to the DESERIALIZED locator -> same chapter as saved.
                mainSync { nav.go(parsed, animated = false) }
                settle(600)
                val afterJson = nav.currentLocator.value
                android.util.Log.i("AnchorRestore", "AFTER-JSON href=${afterJson.href} prog=${progression(afterJson)}")
                assertEquals("JSON-restored locator landed in wrong chapter",
                    saved.href.toString(), afterJson.href.toString())
            } finally {
                scenario.close()
            }
        } finally {
            pub.close()
        }
    }

    /** JS: the target paragraph's own viewport placement after restore — top px from
     *  the viewport top, plus whether it's on-screen. This measures where the RESTORE
     *  TARGET landed (Codex Gate-4 fix), not a nearest-top-paragraph proxy. */
    private fun targetViewport(nav: EpubNavigatorFragment, id: String): JSONObject? {
        val raw = runBlocking(Dispatchers.Main) {
            nav.evaluateJavascript(
                "(function(){var el=document.getElementById('$id');if(!el)return 'null';" +
                    "var r=el.getBoundingClientRect();var ih=window.innerHeight;" +
                    "return JSON.stringify({top:Math.round(r.top),ih:ih," +
                    "visible:(r.top<ih&&r.bottom>0)});})()"
            )
        }?.trim()?.trim('"')?.replace("\\\"", "\"") ?: return null
        return runCatching { JSONObject(raw) }.getOrNull()
    }

    /**
     * Paragraph-precise restore (the real #352 bar): save a PARAGRAPH-precise
     * locator derived from a text selection on a deep paragraph, navigate away,
     * restore, and measure where the TARGET PARAGRAPH itself landed in the viewport.
     * Chapter restore (above) is faithful but coarse; this is the fragment-level
     * probe a saved highlight/CFI needs.
     */
    @Test
    fun paragraphPreciseRestore() {
        val pub = openFixture()
        try {
            val spine = pub.readingOrder
            val (scenario, nav) = launchNavigator(pub)
            try {
                mainSync { nav.go(pub.locatorFromLink(spine[2])!!, animated = false) }
                settle(600)
                // Select a deep paragraph -> Readium yields a fragment-precise locator.
                val targetId = "c3p18"
                runBlocking(Dispatchers.Main) {
                    nav.evaluateJavascript(
                        "(function(){var el=document.getElementById('$targetId');if(!el)return 'NOELEM';" +
                            "var r=document.createRange();r.selectNodeContents(el);" +
                            "var s=window.getSelection();s.removeAllRanges();s.addRange(r);return 'OK';})()"
                    )
                }
                settle(400)
                val saved = runBlocking(Dispatchers.Main) { nav.currentSelection() }?.locator
                assertTrue("no selection locator for $targetId", saved != null)
                android.util.Log.i("AnchorRestore", "PRECISE-SAVED text=${saved!!.text.highlight?.take(12)}")

                // Navigate AWAY, then restore via the paragraph-precise locator.
                mainSync { nav.go(pub.locatorFromLink(spine[0])!!, animated = false) }
                settle(500)
                mainSync { nav.go(saved, animated = false) }
                settle(700)
                // Measure the TARGET paragraph's own viewport placement (sound signal).
                val vp = targetViewport(nav, targetId)
                assertTrue("could not measure target $targetId viewport", vp != null)
                val top = vp!!.optInt("top", 99999)
                val ih = vp.optInt("ih", 1)
                val visible = vp.optBoolean("visible", false)
                val offsetFrac = top.toDouble() / ih
                android.util.Log.i("AnchorRestore",
                    "PRECISE-RESTORED target=$targetId topPx=$top ih=$ih visible=$visible offsetFrac=${"%.3f".format(offsetFrac)}")
                // Tighter-than-visible gate (Codex Gate-4 round 2): the fragment restore
                // must align the TARGET paragraph into the TOP THIRD of the viewport
                // (0 <= offsetFrac < 0.34) — this excludes a restore that lands several
                // paragraphs off (target near the bottom or above the fold), which a bare
                // `visible` check would let pass. It is NOT a same-paragraph gate: the
                // measured ~0.18 offset (~2 paragraphs below top) is RECORDED as the
                // #352-class hardening obligation for WI-4, not asserted as exact.
                assertTrue("fragment restore did not bring target $targetId on-screen (topPx=$top ih=$ih)",
                    visible)
                assertTrue("fragment restore left target $targetId outside the top third (offsetFrac=${"%.3f".format(offsetFrac)}) — restore is wildly off",
                    offsetFrac >= 0.0 && offsetFrac < 0.34)
            } finally {
                scenario.close()
            }
        } finally {
            pub.close()
        }
    }

    @Test
    fun selectionRoundTrip() {
        val pub = openFixture()
        try {
            val spine = pub.readingOrder
            val (scenario, nav) = launchNavigator(pub)
            try {
                mainSync { nav.go(pub.locatorFromLink(spine[1])!!, animated = false) }
                settle(700)
                // Inject a DOM selection over a known paragraph and read its text back.
                val expected = "第2章第3段"
                val read = runBlocking(Dispatchers.Main) {
                    nav.evaluateJavascript(
                        "(function(){var el=document.getElementById('c2p3');if(!el)return 'NOELEM';" +
                            "var r=document.createRange();r.selectNodeContents(el);" +
                            "var s=window.getSelection();s.removeAllRanges();s.addRange(r);" +
                            "return el.textContent;})()"
                    )
                }?.trim()?.trim('"')
                settle(400)
                val selection = runBlocking(Dispatchers.Main) { nav.currentSelection() }
                val highlight = selection?.locator?.text?.highlight
                android.util.Log.i("AnchorRestore", "SELECTION jsRead=${read?.take(12)} currentSelection=${highlight?.take(12)}")

                // DOM is reachable (sanity), THEN the load-bearing claim: Readium
                // surfaces the selection via currentSelection() with the exact
                // paragraph text (Codex Gate-4 — was unasserted before).
                assertTrue("could not reach the navigator content DOM (read=$read)",
                    read != null && read != "NOELEM")
                assertTrue("DOM read mismatch (read=$read)", read!!.contains(expected))
                assertTrue("currentSelection() did not surface the selection (got null)",
                    highlight != null)
                assertTrue("currentSelection highlight '$highlight' missing expected '$expected'",
                    highlight!!.contains(expected))
            } finally {
                scenario.close()
            }
        } finally {
            pub.close()
        }
    }
}
