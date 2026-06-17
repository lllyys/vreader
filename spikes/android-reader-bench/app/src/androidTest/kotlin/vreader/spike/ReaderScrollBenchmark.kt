package vreader.spike

import androidx.fragment.app.testing.launchFragmentInContainer
import androidx.lifecycle.Lifecycle
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.readium.r2.navigator.epub.EpubNavigatorFactory
import org.readium.r2.navigator.epub.EpubNavigatorFragment
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Publication

/**
 * Spike B (#105) WI-2 — instrumented scroll-sweep over the real 1042-chapter CJK
 * corpus (道诡异仙). Opens via Readium-Kotlin 3.3.0, hosts the EPUB navigator in
 * SCROLL mode in-process (no UI automation — ADR-0001 R2), drives a deterministic
 * 250-chapter sweep with animated intra-chapter scrolls, and records frame timing
 * (active-window only), renderer-aware memory trajectory (the eviction signal),
 * and real forward-progress. Writes metrics.json for the host wrapper to pull.
 *
 * Hard asserts are the engine-BLOCKING invariants AND the validity guards the
 * Gate-4 audit demanded: scroll mode actually took effect (not paginated
 * fallback), real forward progress through the book (not just chapter jumps), and
 * bounded TOTAL (host+renderer) PSS. The scroll-smoothness verdict vs the iOS
 * baseline is judged in WI-4 from the JSON — emulator frame timing is variable,
 * so gating on a 5%-jank threshold would flake for reasons unrelated to Readium.
 */
@OptIn(ExperimentalReadiumApi::class)
@RunWith(AndroidJUnit4::class)
class ReaderScrollBenchmark {

    private val instr = InstrumentationRegistry.getInstrumentation()
    private val ctx = instr.targetContext

    private fun arg(name: String, default: Int): Int =
        InstrumentationRegistry.getArguments().getString(name)?.toIntOrNull() ?: default

    private fun mainSync(block: () -> Unit) = instr.runOnMainSync(block)
    private fun settle(ms: Long) {
        instr.waitForIdleSync()
        Thread.sleep(ms)
    }

    @Test
    fun scrollSweep() {
        val corpus = ReaderOpener.corpusFile(ctx)
        assertTrue("corpus missing at ${corpus.absolutePath} (push it first)", corpus.exists())

        val publication: Publication = runBlocking { ReaderOpener.open(ctx, corpus) }
        try {
            runSweep(publication, corpus)
        } finally {
            publication.close()
        }
    }

    private fun runSweep(publication: Publication, corpus: java.io.File) {
        val spine = publication.readingOrder
        assertTrue("expected the 1000+-spine CJK corpus, got ${spine.size}", spine.size > 1000)

        val targetChapters = arg("chapters", 250).coerceAtMost(spine.size)
        val scrollsPerChapter = arg("scrollsPerChapter", 4)

        // Snapshot pre-existing WebView renderers BEFORE launch so sample() can
        // attribute only our session's newly-spawned renderer (Gate-4 round-2).
        val probe = MemoryProbe(instr, ctx)
        probe.snapshotBaseline()

        val factory = EpubNavigatorFactory(publication)
        val scenario = launchFragmentInContainer<EpubNavigatorFragment>(
            factory = factory.createFragmentFactory(
                initialLocator = null,
                initialPreferences = EpubPreferences(scroll = true),
                listener = object : EpubNavigatorFragment.Listener {
                    override fun onExternalLinkActivated(
                        url: org.readium.r2.shared.util.AbsoluteUrl,
                    ) {}
                },
            ),
            initialState = Lifecycle.State.RESUMED,
        )

        try {
            lateinit var navigator: EpubNavigatorFragment
            scenario.onFragment { navigator = it }
            settle(1500) // first-resource render

            // Critical validity guard (Codex Gate-4): prove SCROLL mode actually
            // took effect, not a paginated fallback. Readium's resolved
            // `settings.scroll` is the authoritative signal (the applied
            // EpubSettings after EpubPreferences(scroll=true)); combined with the
            // progression-delta assert below it proves scroll mode + real movement.
            val scrollModeVerified = navigator.settings.value.scroll

            val sampler = FrameSampler()
            val mem = ArrayList<MemSample>()
            val started = System.currentTimeMillis()
            mainSync { sampler.start() }

            var traversed = 0
            var scrollAdvances = 0
            var firstProgression = -1.0
            for (i in 0 until targetChapters) {
                val locator = publication.locatorFromLink(spine[i]) ?: continue
                var moved = false
                mainSync { moved = navigator.go(locator, animated = false) } // jump (not sampled)
                if (moved) traversed++
                settle(150)
                if (firstProgression < 0) {
                    firstProgression = navigatorProgression(navigator)
                }
                repeat(scrollsPerChapter) {
                    if (scrollOnce(navigator, sampler)) scrollAdvances++
                }
                if (i % 10 == 0) mem.add(probe.sample(i))
            }
            mem.add(probe.sample(targetChapters))
            mainSync { sampler.stop() }
            val lastProgression = navigatorProgression(navigator)

            val result = BenchResult(
                corpusBytes = corpus.length(),
                spineCount = spine.size,
                chaptersTraversed = traversed,
                scrollAdvances = scrollAdvances,
                scrollModeVerified = scrollModeVerified,
                firstProgression = firstProgression.coerceAtLeast(0.0),
                lastProgression = lastProgression,
                frameIntervalsMs = sampler.intervalsMs(),
                mem = mem,
                wallClockMs = System.currentTimeMillis() - started,
            )
            val json = result.toJson()
            java.io.File(ctx.getExternalFilesDir(null), "metrics.json").writeText(json.toString(2))
            android.util.Log.i("ReaderBench", "METRICS $json")

            // Engine-blocking invariants + Gate-4 validity guards.
            assertTrue("scroll mode did not take effect (paginated fallback?)", scrollModeVerified)
            assertTrue("traversed only $traversed chapters (<200)", traversed >= 200)
            assertTrue("no scroll advances accepted by navigator", scrollAdvances > 0)
            assertTrue("no real forward progress: $firstProgression -> $lastProgression",
                lastProgression > firstProgression)
            assertTrue("no scroll-motion frames recorded", result.frameIntervalsMs.isNotEmpty())
            assertTrue("memory not sampled", mem.size >= 5)
            val totalLast = mem.last().totalPssKb
            val rendererMax = mem.maxOfOrNull { it.rendererPssKb } ?: 0
            val maxProcs = mem.maxOfOrNull { it.processCount } ?: 0
            assertTrue("WebView renderer memory never captured (host-only = unsound de-risk)",
                rendererMax > 0)
            // Attribution invariant (Codex Gate-4 round-3): exactly host + 1 of OUR
            // renderers. >2 means a foreign WebView sandbox spawned mid-sweep and
            // contaminated rendererPssKb — fail the run rather than report it as valid.
            assertTrue("attributed $maxProcs procs (>2): a foreign WebView sandbox contaminated the run",
                maxProcs <= 2)
            assertTrue("total PSS ballooned to ${totalLast}KB (OOM risk)", totalLast in 1..2_500_000)
        } finally {
            scenario.close()
        }
    }

    /** Whole-publication progression (0..1), or 0 if unavailable. */
    private fun navigatorProgression(nav: EpubNavigatorFragment): Double =
        nav.currentLocator.value.locations.totalProgression ?: 0.0

    /**
     * One animated scroll with the frame sample-window bounded by Readium locator
     * stabilization (Gate-4 round-2 fix): open the window, advance, then keep
     * sampling until progression has moved AND held steady for two reads (the
     * animation finished) — or a hard cap. No fixed settle timer, so fast scrolls
     * don't fold in idle vsync and slow scrolls aren't clipped. Returns whether the
     * navigator accepted the advance.
     */
    private fun scrollOnce(nav: EpubNavigatorFragment, sampler: FrameSampler): Boolean {
        mainSync { sampler.setActive(true) }
        var adv = false
        val before = navigatorProgression(nav)
        mainSync { adv = nav.goForward(animated = true) }
        var last = before
        var moved = false
        var stable = 0
        var waited = 0
        while (waited < 1200 && stable < 2) {
            Thread.sleep(32)
            waited += 32
            val p = navigatorProgression(nav)
            if (p != last) { moved = true; stable = 0; last = p } else if (moved) stable++
        }
        mainSync { sampler.setActive(false) }
        return adv
    }
}
