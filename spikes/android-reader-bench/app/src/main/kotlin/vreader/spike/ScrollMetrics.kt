package vreader.spike

import android.app.Instrumentation
import android.content.Context
import android.os.Debug
import android.os.ParcelFileDescriptor
import android.view.Choreographer
import org.json.JSONArray
import org.json.JSONObject

/**
 * Spike B (#105) WI-2 — in-process frame-timing + (renderer-aware) memory
 * samplers. This is the "macrobenchmark FrameTimingMetric or equivalent" the
 * plan allows: the spike is instrumentation-first / NOT UI-automation-driven
 * (ADR-0001 R2), so we sample Choreographer frame intervals and process memory
 * directly rather than driving a real device swipe under macrobenchmark.
 */

/**
 * Records inter-frame intervals on the main thread while `active`. The active
 * window is NOT a fixed timer (Codex Gate-4 round-2 High): the caller opens it at
 * scroll start and closes it on a real completion signal — Readium locator
 * stabilization (see ReaderScrollBenchmark.scrollOnce). Readium's currentLocator
 * progression updates at scroll completion, not per-frame, so per-frame motion
 * gating records nothing; bounding the window by "progression moved then held
 * steady" is the auditor's suggested locator-stabilization signal and keeps the
 * sample to the real scroll animation rather than an arbitrary settle pad.
 */
class FrameSampler : Choreographer.FrameCallback {
    private val frameNanos = ArrayList<Long>(8192)
    private var lastNanos = 0L
    private var running = false
    @Volatile private var active = false

    /** Call on the main thread. */
    fun start() {
        running = true
        lastNanos = 0L
        Choreographer.getInstance().postFrameCallback(this)
    }

    /** Call on the main thread. */
    fun stop() {
        running = false
        active = false
        Choreographer.getInstance().removeFrameCallback(this)
    }

    /** Open/close the sample window; resets the delta baseline so the gap between
     *  windows is never charged as a frame interval. */
    fun setActive(value: Boolean) {
        active = value
        lastNanos = 0L
    }

    override fun doFrame(frameTimeNanos: Long) {
        if (active && lastNanos != 0L) frameNanos.add(frameTimeNanos - lastNanos)
        lastNanos = frameTimeNanos
        if (running) Choreographer.getInstance().postFrameCallback(this)
    }

    /** Inter-frame deltas (ms) recorded during the bounded scroll windows. */
    fun intervalsMs(): List<Double> = frameNanos.map { it / 1_000_000.0 }
}

/**
 * Renderer-aware memory probe. WebView Chromium renders in a separate sandboxed
 * child process (named `<pkg>:sandboxed_process…`) — host-process PSS alone would
 * NOT measure the renderer eviction that IS ADR-0001 Risk-2 (Codex Gate-4 High).
 * Uses the instrumentation's UiAutomation shell (shell uid) to `dumpsys meminfo`
 * every process whose name starts with our package: the main process plus its
 * WebView renderer child. Reports host / renderer / total PSS separately.
 */
class MemoryProbe(private val instr: Instrumentation, ctx: Context) {
    private val pkg = ctx.packageName

    /**
     * Sandboxed-renderer PIDs already alive BEFORE our navigator launched. WebView
     * renders in a shared sandboxed process under the webview package's uid
     * (`…:sandboxed_process…`), so a name match alone would sum every Chromium
     * sandbox on the device — not only ours (Codex Gate-4 round-2 High). We snapshot
     * the pre-launch set and attribute ONLY newly-spawned renderers to our session;
     * `sample()` reports `processCount` so the test can FAIL the run if no renderer
     * was uniquely attributable rather than silently reporting host-only memory.
     */
    private var baselineSandbox: Set<Int> = emptySet()

    private fun shell(cmd: String): String =
        ParcelFileDescriptor.AutoCloseInputStream(instr.uiAutomation.executeShellCommand(cmd))
            .use { it.readBytes().decodeToString() }

    private val totalPssRe = Regex("TOTAL PSS:\\s+(\\d+)")
    private val totalRowRe = Regex("(?m)^\\s*TOTAL\\s+(\\d+)")

    private fun pssKb(pid: Int): Int {
        val out = shell("dumpsys meminfo --local $pid")
        return totalPssRe.find(out)?.groupValues?.get(1)?.toIntOrNull()
            ?: totalRowRe.find(out)?.groupValues?.get(1)?.toIntOrNull()
            ?: 0
    }

    /** (processName, pid) for every running process. */
    private fun allPids(): List<Pair<String, Int>> =
        shell("ps -A -o PID -o NAME").lineSequence().mapNotNull { line ->
            val parts = line.trim().split(Regex("\\s+"))
            val name = parts.getOrNull(1) ?: return@mapNotNull null
            if (parts.size >= 2) parts[0].toIntOrNull()?.let { name to it } else null
        }.toList()

    private fun sandboxPids(): Set<Int> =
        allPids().filter { it.first.contains("sandboxed_process") }.map { it.second }.toSet()

    /** Call BEFORE launching the navigator, to record pre-existing renderers. */
    fun snapshotBaseline() {
        baselineSandbox = sandboxPids()
    }

    fun sample(chapterIndex: Int): MemSample {
        var host = 0
        var renderer = 0
        var procs = 0
        for ((name, pid) in allPids()) {
            val isHost = name == pkg
            // renderer = sandboxed process spawned AFTER our launch (our session's).
            val isOurRenderer = name.contains("sandboxed_process") && pid !in baselineSandbox
            if (!isHost && !isOurRenderer) continue
            val pss = pssKb(pid)
            if (isHost) host += pss else renderer += pss
            procs++
        }
        return MemSample(
            chapterIndex = chapterIndex,
            hostPssKb = host,
            rendererPssKb = renderer,
            totalPssKb = host + renderer,
            nativeHeapKb = (Debug.getNativeHeapAllocatedSize() / 1024),
            processCount = procs,
        )
    }
}

/** One sample of the memory trajectory at a sweep checkpoint. */
data class MemSample(
    val chapterIndex: Int,
    val hostPssKb: Int,
    val rendererPssKb: Int,
    val totalPssKb: Int,
    val nativeHeapKb: Long,
    val processCount: Int,
)

/** Final benchmark result, serialized to JSON and pulled off-device. */
data class BenchResult(
    val corpusBytes: Long,
    val spineCount: Int,
    val chaptersTraversed: Int,
    val scrollAdvances: Int,
    val scrollModeVerified: Boolean,
    val firstProgression: Double,
    val lastProgression: Double,
    val frameIntervalsMs: List<Double>,
    val mem: List<MemSample>,
    val wallClockMs: Long,
) {
    private fun percentile(sorted: List<Double>, p: Double): Double {
        if (sorted.isEmpty()) return 0.0
        val idx = ((sorted.size - 1) * p).toInt().coerceIn(0, sorted.size - 1)
        return sorted[idx]
    }

    fun toJson(): JSONObject {
        val sorted = frameIntervalsMs.sorted()
        val budget = 1000.0 / 60.0 // 16.6ms
        val jank = frameIntervalsMs.count { it > budget }
        val memArr = JSONArray().apply {
            mem.forEach {
                put(JSONObject().apply {
                    put("chapter", it.chapterIndex)
                    put("hostPssKb", it.hostPssKb)
                    put("rendererPssKb", it.rendererPssKb)
                    put("totalPssKb", it.totalPssKb)
                    put("nativeHeapKb", it.nativeHeapKb)
                    put("processCount", it.processCount)
                })
            }
        }
        val totals = mem.map { it.totalPssKb }
        return JSONObject().apply {
            put("corpusBytes", corpusBytes)
            put("spineCount", spineCount)
            put("chaptersTraversed", chaptersTraversed)
            put("scrollAdvances", scrollAdvances)
            put("scrollModeVerified", scrollModeVerified)
            put("firstProgression", firstProgression)
            put("lastProgression", lastProgression)
            put("progressionDelta", lastProgression - firstProgression)
            put("frameCount", frameIntervalsMs.size)
            put("jankFrames", jank)
            put("jankPercent", if (frameIntervalsMs.isEmpty()) 0.0 else jank * 100.0 / frameIntervalsMs.size)
            put("frameMsP50", percentile(sorted, 0.50))
            put("frameMsP90", percentile(sorted, 0.90))
            put("frameMsP99", percentile(sorted, 0.99))
            put("frameMsMax", sorted.lastOrNull() ?: 0.0)
            put("totalPssFirstKb", totals.firstOrNull() ?: 0)
            put("totalPssLastKb", totals.lastOrNull() ?: 0)
            put("totalPssMaxKb", totals.maxOrNull() ?: 0)
            put("totalPssGrowthKb", (totals.lastOrNull() ?: 0) - (totals.firstOrNull() ?: 0))
            put("rendererPssMaxKb", mem.maxOfOrNull { it.rendererPssKb } ?: 0)
            put("wallClockMs", wallClockMs)
            put("mem", memArr)
        }
    }
}
