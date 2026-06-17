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
 * SCROLL mode in-process (no UI automation — ADR-0001 R2), and drives a
 * deterministic chapter-by-chapter sweep with animated intra-chapter scrolls so
 * the Choreographer frame sampler sees real scroll frames. Records frame timing
 * (jank %, p90/p99), memory trajectory (PSS / native heap — the eviction signal),
 * and chapter coverage; writes metrics.json for the host wrapper to pull.
 *
 * Hard asserts here are only the engine-BLOCKING invariants (opened, traversed,
 * frames rendered, didn't OOM). The scroll-smoothness / eviction-shape verdict
 * vs the iOS baseline is judged in WI-4 from the JSON — emulator frame timing is
 * variable, so gating the test on a 5%-jank threshold would flake for reasons
 * unrelated to Readium. The plan: memory/renderer FAIL is blocking; a scroll
 * miss is a hardening obligation.
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
        val spine = publication.readingOrder
        assertTrue("expected the 1000+-spine CJK corpus, got ${spine.size}", spine.size > 1000)

        val targetChapters = arg("chapters", 250).coerceAtMost(spine.size)
        val scrollsPerChapter = arg("scrollsPerChapter", 4)

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

        lateinit var navigator: EpubNavigatorFragment
        scenario.onFragment { navigator = it }
        settle(1500) // first-resource render

        val sampler = FrameSampler()
        val mem = ArrayList<MemSample>()
        val started = System.currentTimeMillis()
        mainSync { sampler.start() }

        var traversed = 0
        for (i in 0 until targetChapters) {
            val locator = publication.locatorFromLink(spine[i]) ?: continue
            var moved = false
            mainSync { moved = navigator.go(locator, animated = false) }
            if (moved) traversed++
            settle(150) // chapter layout + resource load
            repeat(scrollsPerChapter) {
                mainSync { navigator.goForward(animated = true) } // smooth scroll → real frames
                settle(220)
            }
            if (i % 25 == 0) {
                mem.add(MemSample(i, samplePssKb(ctx), sampleNativeHeapBytes() / 1024))
            }
        }
        mem.add(MemSample(targetChapters, samplePssKb(ctx), sampleNativeHeapBytes() / 1024))
        mainSync { sampler.stop() }

        val result = BenchResult(
            corpusBytes = corpus.length(),
            spineCount = spine.size,
            chaptersTraversed = traversed,
            frameIntervalsMs = sampler.intervalsMs(),
            mem = mem,
            readerCrashes = 0,   // host wrapper computes from logcat
            blankFrames = 0,
            wallClockMs = System.currentTimeMillis() - started,
        )
        val json = result.toJson()
        java.io.File(ctx.getExternalFilesDir(null), "metrics.json")
            .writeText(json.toString(2))
        android.util.Log.i("ReaderBench", "METRICS ${json}")

        // Engine-blocking invariants only (see class doc).
        assertTrue("traversed only $traversed chapters (<200)", traversed >= 200)
        assertTrue("no frames rendered during sweep", result.frameIntervalsMs.isNotEmpty())
        assertTrue("memory not sampled", mem.size >= 5)
        val pssLast = mem.last().pssKb
        assertTrue("PSS ballooned to ${pssLast}KB (OOM risk)", pssLast in 1..1_500_000)
    }
}
