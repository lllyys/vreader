package vreader.spike

import android.app.ActivityManager
import android.content.Context
import android.os.Debug
import android.view.Choreographer
import org.json.JSONArray
import org.json.JSONObject

/**
 * Spike B (#105) WI-2 — in-process frame-timing + memory samplers. This is the
 * "macrobenchmark FrameTimingMetric or equivalent" the plan allows: the spike is
 * instrumentation-first / NOT UI-automation-driven (ADR-0001 R2), so we sample
 * Choreographer frame intervals on the main thread and process memory via
 * ActivityManager rather than driving a real device swipe under macrobenchmark.
 */

/** Records inter-frame intervals on the main thread between start() and stop(). */
class FrameSampler : Choreographer.FrameCallback {
    private val frameNanos = ArrayList<Long>(4096)
    private var lastNanos = 0L
    private var running = false

    /** Call on the main thread. */
    fun start() {
        running = true
        lastNanos = 0L
        Choreographer.getInstance().postFrameCallback(this)
    }

    /** Call on the main thread. */
    fun stop() {
        running = false
        Choreographer.getInstance().removeFrameCallback(this)
    }

    override fun doFrame(frameTimeNanos: Long) {
        if (lastNanos != 0L) frameNanos.add(frameTimeNanos - lastNanos)
        lastNanos = frameTimeNanos
        if (running) Choreographer.getInstance().postFrameCallback(this)
    }

    /** Inter-frame deltas in milliseconds (one per rendered frame after the first). */
    fun intervalsMs(): List<Double> = frameNanos.map { it / 1_000_000.0 }
}

/** Total PSS (KB) for this process — the memory-trajectory signal. */
fun samplePssKb(context: Context): Int {
    val am = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
    val info = am.getProcessMemoryInfo(intArrayOf(android.os.Process.myPid()))
    return info.firstOrNull()?.totalPss ?: 0
}

/** Native heap allocated bytes — cheap, sampled alongside PSS. */
fun sampleNativeHeapBytes(): Long = Debug.getNativeHeapAllocatedSize()

/** One sample of the memory trajectory at a sweep checkpoint. */
data class MemSample(val chapterIndex: Int, val pssKb: Int, val nativeHeapKb: Long)

/** Final benchmark result, serialized to JSON and pulled off-device. */
data class BenchResult(
    val corpusBytes: Long,
    val spineCount: Int,
    val chaptersTraversed: Int,
    val frameIntervalsMs: List<Double>,
    val mem: List<MemSample>,
    val readerCrashes: Int,
    val blankFrames: Int,
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
                    put("pssKb", it.pssKb)
                    put("nativeHeapKb", it.nativeHeapKb)
                })
            }
        }
        val pssVals = mem.map { it.pssKb }
        return JSONObject().apply {
            put("corpusBytes", corpusBytes)
            put("spineCount", spineCount)
            put("chaptersTraversed", chaptersTraversed)
            put("frameCount", frameIntervalsMs.size)
            put("jankFrames", jank)
            put("jankPercent", if (frameIntervalsMs.isEmpty()) 0.0 else jank * 100.0 / frameIntervalsMs.size)
            put("frameMsP50", percentile(sorted, 0.50))
            put("frameMsP90", percentile(sorted, 0.90))
            put("frameMsP99", percentile(sorted, 0.99))
            put("frameMsMax", sorted.lastOrNull() ?: 0.0)
            put("pssFirstKb", pssVals.firstOrNull() ?: 0)
            put("pssLastKb", pssVals.lastOrNull() ?: 0)
            put("pssMaxKb", pssVals.maxOrNull() ?: 0)
            put("pssGrowthKb", (pssVals.lastOrNull() ?: 0) - (pssVals.firstOrNull() ?: 0))
            put("readerCrashes", readerCrashes)
            put("blankFrames", blankFrames)
            put("wallClockMs", wallClockMs)
            put("mem", memArr)
        }
    }
}
