package com.vreader.app.reader.nav

import android.os.Build
import android.os.Debug
import android.os.SystemClock
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.reader.TxtDecoder
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.FixMethodOrder
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters
import java.io.File
import java.security.MessageDigest
import java.util.regex.Matcher
import java.util.regex.Pattern

/**
 * Feature #172 WI-1 — **on-device cost attribution for the TXT TOC scan.** This class measures; it
 * changes nothing. It exists because #139 §5 decided against persistence on a *desktop-JVM* reading
 * of 46–102 ms while the same scan costs 8 300–11 449 ms on the target, and no measurement on the
 * target had ever attributed that cost.
 *
 * **The hypothesis under test (plan §4.2, H1).** Kotlin 2.3.20's `MatcherMatchResult.next()`
 * compiles to `Pattern.matcher(input)` — a brand-new `java.util.regex.Matcher` over the whole
 * 7 029 609-char string, once per match, 1 859 times per extraction. H1 says that construction is
 * O(text length) on Android and O(1) on the desktop JVM, which would explain both the 350×
 * extraction / 4× detection split and the RSS-grows-while-the-Java-heap-is-flat anomaly.
 *
 * **This harness is built to FALSIFY H1, not to confirm it.** Two arms can kill or redirect it:
 *
 * | Arm | What it isolates |
 * | --- | --- |
 * | (a) | `TxtTocRuleEngine.extractHeadings` exactly as shipped — the baseline `Regex.find()/next()` walk |
 * | (b) | the same `Pattern`, ONE reused `Matcher`, identical title/offset/limit/empty-drop logic — layer 1's predicted win |
 * | (c) | `matcher.find()` counting only — separates the match walk from title/list allocation |
 * | (d) | line-start enumeration alone — layer 2's floor, i.e. its best possible outcome |
 * | (e) | `detectBestRule` as shipped + per-rule match counts — tightens H1's predicted ratio to a number |
 * | (g) | N × `pattern.matcher(text)` with NO matching, at THREE text sizes — **H1's decisive arm** |
 * | (h) | K resets and K matches walked five ways — prices the reset, construction and walk paths |
 * | (f) | target-semantic logging: bare `\d`/`\s` vs the repaired classes on the real engine |
 *
 * A flat arm (g) kills H1 and sends WI-2 back to planning — that outcome is named in the plan in
 * advance so it cannot be explained away afterwards. Arm (h) then prices the paths a fix could
 * remove: if the cost survives removing construction alone (i.e. it sits in the reset that
 * `find(int)` performs anyway), a fix that only stops constructing would not close the gap. Arm (h)
 * prices PATHS and deliberately does not claim an exclusive construction-vs-reset split — see its
 * own documentation for exactly what it does and does not establish.
 *
 * **Assertions are EQUIVALENCE, never budgets.** Arms (a)/(b)/(c) must agree on the match count and
 * (a)/(b) element-for-element on `(title, offset)`; arm (h)'s three walks must return the identical
 * offset sequence, which is what makes their timings comparable at all. There is deliberately **no
 * latency assertion anywhere in this class** — a benchmark that gates on the number it was written
 * to discover is not evidence.
 *
 * **Confounder handling** (every arm's number is only worth its controls):
 *  - *JIT warm-up*: every timed arm is preceded by a warm-up that exercises the same shapes, so no
 *    arm pays first-compile cost for the others.
 *  - *Ordering / repetition*: arm (b) is measured both before and after arm (a); arms (c)/(d)/(e)
 *    are read twice; arm (g)'s three sizes and arm (h)'s five sub-arms each run twice in opposite
 *    orders; arm (a) is read once in each of two methods. An ordering or drift effect therefore
 *    shows up as a discrepancy between paired readings rather than hiding inside a single one.
 *    **These are on-device measurements on a loaded emulator, not a JMH steady state** — treat a
 *    figure whose paired readings disagree materially as exploratory, and say so.
 *  - *GC timing*: [gcSettle] runs before every timed ARM, and the "after" memory sample is taken
 *    WITHOUT a collection, so retained native growth is visible instead of being swept away. Arm
 *    (g)'s inter-batch collections are outside its timed regions. Two small in-method diagnostics —
 *    the `Pattern.compile` price and the per-rule sample counts — are NOT separately settled; they
 *    are logged as diagnostics and no conclusion rests on them.
 *  - *Dead-code elimination* (plan §4.3, Gate-2 R2 HIGH): a constructed `Matcher` that is never used
 *    could be scalar-replaced by ART's JIT, reporting a spuriously flat cost and FALSELY KILLING
 *    H1 — the expensive wrong answer, since it would send a correct fix back to planning. Every
 *    construction in arm (g) is therefore published to the `@Volatile` [matcherSink] *inside* the
 *    timed loop (a real reference escape), the escape is asserted, and the loop+sink overhead is
 *    measured separately. The sink performs no match operation, so the arm still isolates
 *    construction.
 *
 * **Memory is a measured output, not a claim** (plan §4.5). Each arm records the Java-heap delta and
 * the process-PSS delta around a single pass. The plan commits three readings in advance: materially
 * lower growth in the reused-`Matcher` arm, comparable growth, or too noisy to tell.
 *
 * **What a PSS delta can and cannot support** (Gate-4 R2 Medium). `totalPss` is WHOLE-PROCESS state
 * sampled without a post-pass collection, so a large delta on one arm and a small one on another
 * shows that the growth travels with that code path and disappears when the path changes — an
 * association, and a decision-grade one. It cannot distinguish a native input attachment from any
 * other transient the same walk provokes, so it does not by itself prove that the growth and the
 * latency are the SAME defect. State it as "same path, removed by the same rewrite"; do not upgrade
 * it to causal identity on this evidence alone.
 *
 * **Fixture — real book first, and the fallback is FAILURE, not synthesis.** Identity is pinned by
 * SHA-256 over the pushed bytes plus the decoded character count, so a same-sized stand-in cannot
 * pass. The connected task wipes `/sdcard/Android/data/com.vreader.app/files/` at run end, so the
 * book must be re-pushed EVERY run:
 *
 * ```
 * adb -s emulator-5554 shell mkdir -p /sdcard/Android/data/com.vreader.app/files
 * adb -s emulator-5554 push test-books/books/txt/黑暗血时代.txt \
 *     /sdcard/Android/data/com.vreader.app/files/perf-cjk.txt
 * ```
 *
 * **Collecting the numbers.** logcat is the PRIMARY channel — read it retrospectively after the run
 * finishes (rule 49: never stream a detached capture alongside it, and never drive the emulator
 * while instrumentation is in flight):
 *
 * ```
 * adb -s emulator-5554 logcat -d -s WI172-COST:I
 * ```
 *
 * The same lines are also appended to `filesDir/wi172-cost-report.txt`, but that is a SECONDARY
 * channel with a stated limitation: `connectedAndroidTest` **uninstalls the app when the run ends**,
 * which deletes internal storage along with it, so the file only survives a run driven by
 * `installDebugAndroidTest` + `am instrument` (which leaves the app in place). Do not rely on it
 * after a plain `connectedDebugAndroidTest`.
 *
 * Run ONE class per connected invocation, and never drive the emulator while it runs (rule 52).
 * Method order is pinned so the log reads in a fixed sequence. Two methods each run one full
 * baseline extraction; on a 2.5 GB emulator that is where the process peaks (the `lowmemorykiller`
 * truncated #139 WI-8 runs at ~1.4 GB RSS). If a run is truncated, reboot the emulator or split the
 * class by `#method`.
 */
@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class TxtTocScanCostTest {

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()

    /**
     * Arm (g)'s non-elidable sink: the constructed `Matcher` ITSELF is stored in a `@Volatile`
     * field, which is a genuine reference escape — ART cannot scalar-replace an object published to
     * a volatile field, and cannot elide constructor initialisation whose result another thread may
     * legally read. An earlier revision accumulated only `System.identityHashCode(m)`; that forces
     * identity but is NOT proof that the rest of the construction is observable (Gate-4 Medium), and
     * a spuriously flat result here would FALSELY KILL H1 — the one expensive wrong answer.
     *
     * Holding the last `Matcher` alive retains at most one input attachment, which is negligible
     * next to the batch the loop has just allocated, and the field is cleared between batches.
     */
    @Volatile
    private var matcherSink: Matcher? = null

    /** The same escape for the overhead baseline, so the two loops have identical sink shapes. */
    @Volatile
    private var objectSink: Any? = null

    /**
     * How many times a sink was written. Deliberately a PLAIN counter: its final value is correct
     * however the JIT schedules it, and it answers "was the loop actually executed" without the
     * false-negative an `Int` accumulator has (a sum of hashes can legitimately be zero — Gate-4
     * Low). It is not part of the escape; [matcherSink] is.
     */
    private var sinkWrites: Long = 0

    private companion object {
        const val TAG = "WI172-COST"
        const val REPORT_FILE = "wi172-cost-report.txt"

        /** The pushed real 14 MB CJK novel, pinned by content digest (a stable local fixture). */
        const val REAL_BOOK_FILE = "perf-cjk.txt"
        const val REAL_BOOK_BYTES = 14_059_220L
        const val REAL_BOOK_BYTES_TOLERANCE = 1_000L
        const val REAL_BOOK_SHA256 = "04d60f6d93256c0d82f714ad1237a57ca88dcd469fb37bef231af062c543cfe4"

        /** Plan §5, measured on the real book: 1 859 chapters over 7 029 609 UTF-16 code units. */
        const val EXPECTED_CHARS_UTF16 = 7_029_609
        const val EXPECTED_HEADINGS = 1_859
        const val EXPECTED_WINNING_RULE_ID = 1

        /** `TxtMdTocProvider.SCAN_LIMIT` — `MAX_TOC_ENTRIES + 1`, so arm (a) walks to end-of-text. */
        const val SCAN_LIMIT = 50_001

        /** Arm (h): how many matches (or resets) each of the five sub-arms performs. */
        const val WALK_MATCHES = 200

        /** Arm (h)'s warm-up walk length — enough to JIT the five shapes, small enough to be free. */
        const val WARMUP_MATCHES = 20

        /** Arms (a)/(b)/(c) warm-up prefix: big enough to JIT the walks, small enough to be free. */
        const val WARMUP_PREFIX_CHARS = 512 * 1024

        /** Arm (g) — untimed constructions that JIT the path before anything is measured. */
        const val WARMUP_CONSTRUCTIONS = 32

        /** Arm (g) — a short timed probe used ONLY to size the real loop (see [TARGET_TIMED_NS]). */
        const val PROBE_CONSTRUCTIONS = 32

        /**
         * Arm (g) sizing — a TIME budget, not a cost cliff.
         *
         * Each text size is measured for roughly the same wall-clock duration, so no size is left
         * averaged over a handful of noise-dominated iterations. The iteration count is derived from
         * a probe as `TARGET_TIMED_NS / probe_ns_per` and clamped, so a noisy probe shifts only HOW
         * MANY iterations are averaged, never the per-iteration figure itself. An earlier revision
         * classified each size "expensive"/"cheap" against a 5 µs threshold; the probe's own noise
         * floor sits near that threshold for a sub-microsecond operation, so the branch was decided
         * by noise and the small sizes stayed noise-dominated at 200 iterations.
         *
         * **What equal DURATION does not buy** (Gate-4 R2 Medium): it does not equalise the
         * execution regimes. A small input reaches its iteration count in one unbroken batch while
         * the book runs dozens of batches separated by collections; JIT hotness follows invocation
         * count, not elapsed time. Equal duration makes each size's average well-conditioned; the
         * reversed second round is what exposes drift. Neither makes the fitted per-character
         * coefficient a high-precision constant — read it as an order-of-magnitude slope.
         */
        const val TARGET_TIMED_NS = 1_200_000_000.0
        const val MIN_CONSTRUCTIONS = 200
        const val MAX_CONSTRUCTIONS = 200_000

        /** Hard wall-clock stop per size per round, INCLUDING the untimed inter-batch settles. */
        const val TIME_BUDGET_MS = 6_000L

        /**
         * Memory guard. Batching is not a timing device: the collection between batches is outside
         * every timed region and the reported total is the sum of the timed regions. Its only job is
         * to cap live native input attachments — under H1 each construction pins `2 × chars` bytes
         * until a Java collection runs, and an unbroken loop over the 14 MB book reaches multiple
         * gigabytes, above where the `lowmemorykiller` has already taken this app once. A batch that
         * attaches less than [SETTLE_ATTACH_BYTES] needs no settle at all, which is what lets a small
         * input be averaged over many iterations in one clean timed region.
         */
        const val BATCH_ATTACH_BYTES = 256L * 1024 * 1024
        const val SETTLE_ATTACH_BYTES = 64L * 1024 * 1024
        const val BATCH_SETTLE_MS = 100L

        /** How often the timed construction loop checks its wall-clock budget (a power-of-two mask). */
        const val BUDGET_CHECK_MASK = 0x3F

        /**
         * Arm (g)'s text sizes. THREE points, not two: two sizes give only a ratio, three let each
         * model be checked against a HELD-OUT point — the length-proportional model is fitted from
         * the outer two and must then predict the middle one, while the constant-cost model predicts
         * all three are equal (Gate-4 R1 High: a bare ratio can neither establish flatness nor
         * quantify scaling). With no variance estimate and no pre-registered threshold this
         * discriminates "roughly constant" from "roughly proportional" over the sampled range; it is
         * not a falsification of asymptotic complexity. See the arm's own KDoc.
         */
        const val SHORT_TEXT_CHARS = 64
        const val MID_TEXT_CHARS = 512 * 1024

        /** How many `Pattern.compile` calls are timed to price arm (a)'s in-band compilation. */
        const val COMPILE_SAMPLES = 20

        // Java's non-ASCII regex line terminators, built from their CODE POINTS rather than written
        // literally: U+0085 NEL, U+2028 LINE SEPARATOR and U+2029 PARAGRAPH SEPARATOR are invisible
        // in a source file, and #139's Gate-2 rounds 3 and 4 both caught invisible characters being
        // silently normalised. `TxtTocRules.INDENT` spells U+3000 the same way for the same reason.
        val NEL = Char(0x0085)
        val LINE_SEPARATOR = Char(0x2028)
        val PARAGRAPH_SEPARATOR = Char(0x2029)

        /** U+3000 IDEOGRAPHIC SPACE — the normal separator in Chinese typesetting (arm (f)). */
        val IDEOGRAPHIC_SPACE = Char(0x3000)

        /**
         * What `^` may follow under MULTILINE with default bounds (arm (d)). Vertical tab and form
         * feed are NOT Java regex line terminators and are deliberately absent.
         */
        fun isLineTerminator(c: Char) =
            c == '\n' || c == '\r' || c == NEL || c == LINE_SEPARATOR || c == PARAGRAPH_SEPARATOR
    }

    /** Memory hygiene between methods: every method holds a 14 MB decoded copy of the real book. */
    @After
    fun releaseMemory() = gcSettle()

    // ---- fixture (real book; requireNotNull, never a synthetic fallback) --------------------------

    private fun realBookFileOrNull(): File? {
        val dir = instrumentation.targetContext.getExternalFilesDir(null) ?: return null
        val f = File(dir, REAL_BOOK_FILE)
        if (!f.exists() || !f.canRead()) return null
        if (kotlin.math.abs(f.length() - REAL_BOOK_BYTES) > REAL_BOOK_BYTES_TOLERANCE) {
            Log.w(TAG, "$REAL_BOOK_FILE is ${f.length()} bytes, expected $REAL_BOOK_BYTES → not the real book")
            return null
        }
        return f
    }

    /**
     * The real book decoded exactly as the reader decodes it, with identity proven by CONTENT.
     *
     * The byte size is a cheap early diagnostic only; the digest is the identity check, because a
     * same-sized synthetic corpus would sail straight through a size comparison. A missing or wrong
     * fixture fails loudly here — a cost attribution measured on a stand-in would be worthless, and
     * silently false-greening on one is a lesson this repo has already paid for once (#138).
     */
    private fun requireRealBookText(): String {
        val file = requireNotNull(realBookFileOrNull()) {
            "WI-1 requires the REAL 14 MB CJK book at getExternalFilesDir(null)/$REAL_BOOK_FILE " +
                "($REAL_BOOK_BYTES bytes). Push it before the run: adb push " +
                "test-books/books/txt/黑暗血时代.txt " +
                "/sdcard/Android/data/com.vreader.app/files/$REAL_BOOK_FILE"
        }
        val bytes = file.readBytes()
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it) }
        assertEquals("the pushed fixture must BE 黑暗血时代.txt (content digest)", REAL_BOOK_SHA256, digest)
        val text = TxtDecoder.decode(bytes).text
        assertEquals("the decoded book must be the plan's corpus", EXPECTED_CHARS_UTF16, text.length)
        return text
    }

    /** The winning rule, detected on the real text exactly as production detects it. */
    private fun requireWinningRule(text: String): TxtTocRule {
        val rule = requireNotNull(runBlocking { TxtTocRuleEngine.detectBestRule(text) }) {
            "detection found no rule for the real book"
        }
        assertEquals("detection must land on the plan's winning rule", EXPECTED_WINNING_RULE_ID, rule.id)
        return rule
    }

    /**
     * The winning rule's `Pattern`, compiled with MULTILINE and nothing else — the exact flags
     * `TxtTocRuleEngine.compile` uses (`RegexOption.MULTILINE` IS `Pattern.MULTILINE`), so every
     * hand-written arm below matches what the shipped engine matches.
     */
    private fun compileWinning(rule: TxtTocRule): Pattern =
        Pattern.compile(rule.pattern, Pattern.MULTILINE)

    // ---- measurement plumbing ---------------------------------------------------------------------

    private fun gcSettle() {
        System.gc()
        System.runFinalization()
        Thread.sleep(250)
        System.gc()
        Thread.sleep(100)
    }

    private class Mem(val heapKb: Long, val pssKb: Long)

    private fun sampleMemory(): Mem {
        val rt = Runtime.getRuntime()
        val heapKb = (rt.totalMemory() - rt.freeMemory()) / 1024
        val pssKb = Debug.MemoryInfo().also { Debug.getMemoryInfo(it) }.totalPss.toLong()
        return Mem(heapKb, pssKb)
    }

    private class Arm<T>(val ms: Long, val value: T, val heapDeltaKb: Long, val pssDeltaKb: Long)

    /**
     * Run [block] once, timed, with a Java-heap and process-PSS sample either side.
     *
     * The "after" sample is taken with NO collection in between: the point is to see what a single
     * pass leaves retained, and a `System.gc()` there would sweep exactly the signal being measured.
     * Both samples sit outside the timed region, so `Debug.getMemoryInfo`'s own cost never lands in
     * the latency. PSS is whole-process and confounded by anything else the device is doing — it is
     * reported as a signal, never as "what the arm costs".
     */
    private fun <T> arm(label: String, block: () -> T): Arm<T> {
        gcSettle()
        val before = sampleMemory()
        val t0 = SystemClock.elapsedRealtime()
        val value = block()
        val ms = SystemClock.elapsedRealtime() - t0
        val after = sampleMemory()
        report(
            "ARM $label ms=$ms heap_kb=${before.heapKb}->${after.heapKb} " +
                "heap_delta_kb=${after.heapKb - before.heapKb} pss_kb=${before.pssKb}->${after.pssKb} " +
                "pss_delta_kb=${after.pssKb - before.pssKb}",
        )
        return Arm(ms, value, after.heapKb - before.heapKb, after.pssKb - before.pssKb)
    }

    /**
     * Emit to logcat (the primary channel) and, best-effort, to internal storage.
     *
     * The file is SECONDARY and does not survive a plain `connectedAndroidTest`, which uninstalls
     * the app at run end and deletes internal storage with it — see the class documentation. Read
     * the numbers with `adb logcat -d -s WI172-COST:I` after the run.
     */
    private fun report(line: String) {
        Log.i(TAG, line)
        runCatching {
            File(instrumentation.targetContext.filesDir, REPORT_FILE)
                .appendText("${System.currentTimeMillis()} $line\n")
        }
    }

    // ---- the walks under measurement ---------------------------------------------------------------

    private class Walk(val headings: List<DetectedHeading>, val rawMatches: Int, val hitLimit: Boolean)

    /**
     * Arm (b) — `extractHeadings`' logic with ONE `Matcher` for the whole scan.
     *
     * Deliberately mirrors the shipped body line for line (whole-match trim as the title, `start()`
     * as the offset, empty titles dropped and not counted against [limit], the limit stopping the
     * SCAN rather than truncating a materialised list, a plain `ArrayList` so the allocation profile
     * is the same). It lives here rather than in production because WI-1 changes no production
     * code — WI-2 owns that.
     */
    private fun walkReused(text: String, pattern: Pattern, limit: Int): Walk {
        val headings = ArrayList<DetectedHeading>()
        var raw = 0
        val m = pattern.matcher(text)
        while (m.find()) {
            raw++
            val title = m.group().trim()
            if (title.isNotEmpty()) {
                headings.add(DetectedHeading(title = title, sourceOffsetUtf16 = m.start()))
                if (headings.size == limit) return Walk(headings, raw, hitLimit = true)
            }
        }
        return Walk(headings, raw, hitLimit = false)
    }

    /** Arm (c) — the same walk with no `group()`, no `trim()`, no list: the match walk alone. */
    private fun countReused(text: String, pattern: Pattern): Int {
        var n = 0
        val m = pattern.matcher(text)
        while (m.find()) n++
        return n
    }

    /**
     * Arm (d) — every position at which Java's MULTILINE `^` can succeed: index 0, or immediately
     * after a line terminator, except between the CR and LF of a CRLF pair, and never at
     * end-of-input (plan §5.2's theorem). One linear pass; this is the floor layer 2 could reach.
     */
    private fun countLineStarts(text: String): Int {
        val n = text.length
        if (n == 0) return 0
        var count = 1
        var i = 0
        while (i < n) {
            val c = text[i]
            if (isLineTerminator(c)) {
                var next = i + 1
                if (c == '\r' && next < n && text[next] == '\n') next++
                if (next < n) count++
                i = next
            } else {
                i++
            }
        }
        return count
    }

    /** `TxtTocRuleEngine.sampleOf` re-expressed here (it is `internal` to the app module). */
    private fun sampleOf(text: String): String {
        val size = TxtTocRuleEngine.SAMPLE_SIZE_UTF16
        if (text.length <= size) return text
        var end = size
        if (text[end - 1].isHighSurrogate() && text[end].isLowSurrogate()) end--
        return text.substring(0, end)
    }

    /** JIT the shipped walk, the reused walk, the counting walk and the line scan before timing. */
    private fun warmUpWalks(text: String, pattern: Pattern, rule: TxtTocRule) {
        val prefix = text.substring(0, minOf(text.length, WARMUP_PREFIX_CHARS))
        runBlocking { TxtTocRuleEngine.extractHeadings(prefix, rule, SCAN_LIMIT) }
        walkReused(prefix, pattern, SCAN_LIMIT)
        countReused(prefix, pattern)
        countLineStarts(prefix)
        gcSettle()
    }

    // ---- 1. equivalence: the arms describe the SAME scan -------------------------------------------

    /**
     * The precondition for every timing in this class: arms (a), (b) and (c) walk the same matches.
     *
     * A faster arm that found different headings would not be a measurement of anything. So the
     * count is checked three ways and the `(title, offset)` sequence element-for-element between the
     * shipped walk and the reused-`Matcher` walk — the same differential-oracle technique #139 WI-5
     * used for `txtTocIndexFor`. This method asserts only equality; its timings are logged.
     */
    @Test
    fun armsAgreeOnHeadings() {
        val text = requireRealBookText()
        val rule = requireWinningRule(text)
        val pattern = compileWinning(rule)
        warmUpWalks(text, pattern, rule)

        val shipped = arm("a-shipped-extractHeadings") {
            runBlocking { TxtTocRuleEngine.extractHeadings(text, rule, SCAN_LIMIT) }
        }
        val reused = arm("b-reused-matcher") { walkReused(text, pattern, SCAN_LIMIT) }
        val counted = arm("c-find-only") { countReused(text, pattern) }

        report(
            "EQUIVALENCE shipped=${shipped.value.headings.size} reused=${reused.value.headings.size} " +
                "raw_matches=${reused.value.rawMatches} find_only=${counted.value} " +
                "shipped_hit_limit=${shipped.value.hitLimit} reused_hit_limit=${reused.value.hitLimit}",
        )

        assertEquals(
            "the shipped walk must find the real book's stated chapter count",
            EXPECTED_HEADINGS, shipped.value.headings.size,
        )
        assertEquals(
            "the reused-Matcher walk must find the SAME number of headings",
            shipped.value.headings.size, reused.value.headings.size,
        )
        assertEquals(
            "arm (c)'s bare find() walk must see the same matches the reused walk saw",
            reused.value.rawMatches, counted.value,
        )
        assertEquals(
            "arms (a)/(b)/(c) must agree on the plan's stated match count",
            EXPECTED_HEADINGS, counted.value,
        )
        assertTrue("the shipped walk must not hit the scan limit on this book", !shipped.value.hitLimit)
        assertTrue("the reused walk must not hit the scan limit on this book", !reused.value.hitLimit)

        // Element-for-element, reported at the FIRST divergence rather than as a bare count mismatch.
        shipped.value.headings.forEachIndexed { i, expected ->
            val actual = reused.value.headings[i]
            assertEquals("heading $i title diverges", expected.title, actual.title)
            assertEquals(
                "heading $i offset diverges (title '${expected.title}')",
                expected.sourceOffsetUtf16, actual.sourceOffsetUtf16,
            )
        }
        report("EQUIVALENCE-DETAIL all ${shipped.value.headings.size} (title,offset) pairs identical")
    }

    // ---- 2. target-semantic logging (arm f) --------------------------------------------------------

    /**
     * Arm (f) — records on the TARGET what #139's D1/D1b repairs currently rest on desktop-JVM unit
     * tests for, and asserts only the half that is a product claim.
     *
     * The bare-`\d` / bare-`\s` booleans are LOGGED, not gated: they are weak proxies for engine
     * identity, and arm (g) answers the cost question directly without needing to know which engine
     * is underneath. What IS asserted is the repair itself — that `TxtTocRules.DIGIT` matches a
     * full-width digit and `TxtTocRules.WS` matches U+3000 IDEOGRAPHIC SPACE on this device —
     * because a CJK book whose headings separate their numerals with U+3000 gets no Contents at all
     * if that fails.
     */
    @Test
    fun logsTargetRegexSemantics() {
        // Full-width digits are VISIBLE characters, so they stand literally; U+3000 is invisible and
        // is therefore built from its code point (same rule as the line terminators above).
        val fullWidthDigits = "第１２章"
        val ideographicSpaced = "第" + IDEOGRAPHIC_SPACE + "一"
        val bareDigitMatchesFullWidth = Pattern.compile("第\\d+章").matcher(fullWidthDigits).find()
        val bareSpaceMatchesIdeographic = Pattern.compile("第\\s一").matcher(ideographicSpaced).find()
        val repairedDigit = Pattern.compile("第${TxtTocRules.DIGIT}+章").matcher(fullWidthDigits).find()
        val repairedSpace = Pattern.compile("第${TxtTocRules.WS}一").matcher(ideographicSpaced).find()

        report(
            "TARGET-SEMANTICS sdk=${Build.VERSION.SDK_INT} " +
                "bare_d_matches_fullwidth=$bareDigitMatchesFullWidth " +
                "bare_s_matches_u3000=$bareSpaceMatchesIdeographic " +
                "repaired_DIGIT_matches_fullwidth=$repairedDigit " +
                "repaired_WS_matches_u3000=$repairedSpace",
        )

        assertTrue("TxtTocRules.DIGIT must match a full-width digit ON THE TARGET", repairedDigit)
        assertTrue("TxtTocRules.WS must match U+3000 ON THE TARGET", repairedSpace)
    }

    // ---- 3. arm (h): construction vs reset ---------------------------------------------------------

    /**
     * Arm (h) — five sub-arms over the same text and the same K positions, so the scanning work is
     * identical wherever there is any, and only the per-match ceremony differs:
     *
     *  - **h0a** one `Matcher`, K × `reset(text)` — re-attaching the input, NO matching at all.
     *  - **h0b** one `Matcher`, K × `reset()` — the bookkeeping reset that does not re-attach input.
     *  - **h1** one `Matcher`, K × no-arg `find()` — the pure walk.
     *  - **h2** one `Matcher`, K × `find(resume_i)` — the walk plus whatever `find(int)` resets.
     *  - **h3** K fresh `Matcher`s, each `find(resume_i)` — h2 plus K constructions. This is exactly
     *    the shape Kotlin's `MatchResult.next()` produces.
     *
     * **Why h0a/h0b exist** (Gate-4 R1 High): differences alone cannot decompose this.
     * `Pattern.matcher` itself performs a reset and `find(int)` performs another, so an expensive
     * reset shows up in BOTH `h2 − h1` and `h3 − h2`. h0a and h0b measure the reset DIRECTLY with no
     * matching at all, which anchors the arithmetic instead of inferring it.
     *
     * **What the numbers are, stated precisely** (Gate-4 R2 High — the previous wording claimed more
     * than this design can deliver). h0a and h0b are DIRECT measurements of the two reset forms.
     * Everything else is a PATH cost, not an exclusive component cost:
     *
     *  - `find_int_minus_find` is what the `find(int)` path costs over the `find()` path. AOSP's
     *    `find(int)` has its own entry sequence, so this is "the find(int) path", which h0b's direct
     *    reading merely corroborates — it is not by itself proof that the excess IS the reset method.
     *  - `construction_incl_own_reset` is what the fresh-matcher path costs over the reused one.
     *  - `construction_net_of_input_reset` is a RESIDUAL of two separately-settled whole walks. If it
     *    comes out negative, that does not mean construction has negative cost: it means the two
     *    costs are not additive at this resolution, i.e. construction is at most about one reset and
     *    the allocation itself is lost in the noise. Read a negative value as "below the
     *    experiment's resolution", never as a measurement.
     *
     * An exclusive percentage split between construction and reset is therefore NOT established here
     * and must not be quoted from this arm. What IS established, and what a fix has to act on: both
     * reset forms are expensive, and both the fresh-matcher path and the `find(int)` path are
     * millisecond-scale on this input, while a full h1 walk step (reused matcher, no-arg `find()`)
     * costs roughly 3 % of a full h3 step — i.e. the per-match saving is a factor of tens, read
     * from the h1-vs-h3 totals rather than from any component difference.
     *
     * `resume_i` is the position `next()` itself would resume from (the previous match's end, +1
     * after an empty match), so h1/h2/h3 scan the same gaps rather than one of them starting
     * conveniently on top of its match.
     *
     * Every sub-arm runs twice in OPPOSITE orders; an ordering or JIT effect shows up as a
     * discrepancy between the rounds instead of masquerading as a result.
     */
    @Test
    fun reportsConstructionVsResetSplit() {
        val text = requireRealBookText()
        val rule = requireWinningRule(text)
        val pattern = compileWinning(rule)
        val resume = resumePositions(pattern, text, WALK_MATCHES)

        // Warm-up on a smaller K — untimed.
        val warmResume = resumePositions(pattern, text, WARMUP_MATCHES)
        resetLoop(pattern, text, WARMUP_MATCHES, reattachInput = true)
        resetLoop(pattern, text, WARMUP_MATCHES, reattachInput = false)
        walkNoArg(pattern, text, WARMUP_MATCHES)
        walkReusedFindFrom(pattern, text, warmResume)
        walkFreshFindFrom(pattern, text, warmResume)
        gcSettle()

        val r1h0a = timeNs("h0a-round1-reset-with-input") { resetLoop(pattern, text, WALK_MATCHES, true) }
        val r1h0b = timeNs("h0b-round1-reset-no-input") { resetLoop(pattern, text, WALK_MATCHES, false) }
        val r1h1 = timeWalk("h1-round1-reused-noarg-find") { walkNoArg(pattern, text, WALK_MATCHES) }
        val r1h2 = timeWalk("h2-round1-reused-find-from") { walkReusedFindFrom(pattern, text, resume) }
        val r1h3 = timeWalk("h3-round1-fresh-find-from") { walkFreshFindFrom(pattern, text, resume) }
        val r2h3 = timeWalk("h3-round2-fresh-find-from") { walkFreshFindFrom(pattern, text, resume) }
        val r2h2 = timeWalk("h2-round2-reused-find-from") { walkReusedFindFrom(pattern, text, resume) }
        val r2h1 = timeWalk("h1-round2-reused-noarg-find") { walkNoArg(pattern, text, WALK_MATCHES) }
        val r2h0b = timeNs("h0b-round2-reset-no-input") { resetLoop(pattern, text, WALK_MATCHES, false) }
        val r2h0a = timeNs("h0a-round2-reset-with-input") { resetLoop(pattern, text, WALK_MATCHES, true) }

        // The equivalence that makes the timings comparable: every matching sub-arm found the same
        // matches. h0a/h0b match nothing, so they are checked differently — see below.
        assertEquals("arm (h) must walk the requested number of matches", WALK_MATCHES, r1h1.second.size)
        listOf(
            "h2-round1" to r1h2, "h3-round1" to r1h3,
            "h3-round2" to r2h3, "h2-round2" to r2h2, "h1-round2" to r2h1,
        ).forEach { (name, walk) ->
            assertTrue(
                "$name must have found the SAME $WALK_MATCHES match offsets as h1-round1 — otherwise " +
                    "the sub-arms are not doing the same work and their times are not comparable",
                walk.second.contentEquals(r1h1.second),
            )
        }
        // h0a/h0b's own check: a reset loop that had been optimised away, or that left the matcher
        // unusable, would make its timing meaningless. Both must leave a matcher that still finds
        // the SAME first match the walking sub-arms found.
        assertEquals(
            "a matcher reset with reset(text) must still find the first match at the same offset",
            r1h1.second.first(), firstMatchAfterResets(pattern, text, reattachInput = true),
        )
        assertEquals(
            "a matcher reset with reset() must still find the first match at the same offset",
            r1h1.second.first(), firstMatchAfterResets(pattern, text, reattachInput = false),
        )

        val k = WALK_MATCHES.toDouble()
        val resetWithInput1 = r1h0a / k
        val resetWithInput2 = r2h0a / k
        val resetNoInput1 = r1h0b / k
        val resetNoInput2 = r2h0b / k
        val findIntExtra1 = (r1h2.first - r1h1.first) / k
        val findIntExtra2 = (r2h2.first - r2h1.first) / k
        val constructionInclReset1 = (r1h3.first - r1h2.first) / k
        val constructionInclReset2 = (r2h3.first - r2h2.first) / k
        report(
            "ARM-H k=$WALK_MATCHES text_chars=${text.length} " +
                "round1_ns h0a=$r1h0a h0b=$r1h0b h1=${r1h1.first} h2=${r1h2.first} h3=${r1h3.first} " +
                "round2_ns h0a=$r2h0a h0b=$r2h0b h1=${r2h1.first} h2=${r2h2.first} h3=${r2h3.first} " +
                "reset_with_input_ns_per_op=${fmt(resetWithInput1)}/${fmt(resetWithInput2)} " +
                "reset_no_input_ns_per_op=${fmt(resetNoInput1)}/${fmt(resetNoInput2)} " +
                "find_int_minus_find_ns_per_op=${fmt(findIntExtra1)}/${fmt(findIntExtra2)} " +
                "construction_incl_own_reset_ns_per_op=" +
                "${fmt(constructionInclReset1)}/${fmt(constructionInclReset2)} " +
                "construction_net_of_input_reset_ns_per_op=" +
                "${fmt(constructionInclReset1 - resetWithInput1)}/${fmt(constructionInclReset2 - resetWithInput2)}",
        )
    }

    /** Two-decimal formatting, used everywhere a derived per-op figure is reported. */
    private fun fmt(v: Double) = "%.1f".format(v)

    /**
     * h0a / h0b — K resets with NO matching. The `Matcher` is published to the volatile sink each
     * iteration so the loop cannot be elided; `reset` returns `this`, so the sink also proves the
     * call happened rather than a hoisted constant being stored.
     */
    private fun resetLoop(pattern: Pattern, text: String, k: Int, reattachInput: Boolean) {
        val m = pattern.matcher(text)
        for (i in 0 until k) {
            matcherSink = if (reattachInput) m.reset(text) else m.reset()
            sinkWrites++
        }
    }

    /** The offset the first match lands at after a reset loop — h0a/h0b's own usability check. */
    private fun firstMatchAfterResets(pattern: Pattern, text: String, reattachInput: Boolean): Int {
        val m = pattern.matcher(text)
        repeat(WARMUP_MATCHES) { if (reattachInput) m.reset(text) else m.reset() }
        check(m.find()) { "a reset matcher must still be able to find" }
        return m.start()
    }

    /** Time a block that returns nothing measurable but must not be elided. */
    private fun timeNs(label: String, block: () -> Unit): Long {
        gcSettle()
        val t0 = System.nanoTime()
        block()
        val ns = System.nanoTime() - t0
        report("ARM $label ns=$ns")
        return ns
    }

    /** Timed walk returning `(elapsedNs, the match offsets it found)`. */
    private fun timeWalk(label: String, block: () -> IntArray): Pair<Long, IntArray> {
        gcSettle()
        val t0 = System.nanoTime()
        val offsets = block()
        val ns = System.nanoTime() - t0
        report("ARM $label ns=$ns matches=${offsets.size}")
        return ns to offsets
    }

    /** The positions `MatchResult.next()` resumes from, for the first [k] matches. */
    private fun resumePositions(pattern: Pattern, text: String, k: Int): IntArray {
        val out = IntArray(k)
        val m = pattern.matcher(text)
        var pos = 0
        for (i in 0 until k) {
            out[i] = pos
            require(m.find(pos)) { "the real book must contain at least $k matches (none at $i)" }
            pos = if (m.end() == m.start()) m.end() + 1 else m.end()
        }
        return out
    }

    private fun walkNoArg(pattern: Pattern, text: String, k: Int): IntArray {
        val out = IntArray(k)
        val m = pattern.matcher(text)
        for (i in 0 until k) {
            check(m.find()) { "ran out of matches at $i" }
            out[i] = m.start()
        }
        return out
    }

    private fun walkReusedFindFrom(pattern: Pattern, text: String, resume: IntArray): IntArray {
        val out = IntArray(resume.size)
        val m = pattern.matcher(text)
        for (i in resume.indices) {
            check(m.find(resume[i])) { "ran out of matches at $i" }
            out[i] = m.start()
        }
        return out
    }

    private fun walkFreshFindFrom(pattern: Pattern, text: String, resume: IntArray): IntArray {
        val out = IntArray(resume.size)
        for (i in resume.indices) {
            val m = pattern.matcher(text)
            check(m.find(resume[i])) { "ran out of matches at $i" }
            out[i] = m.start()
        }
        return out
    }

    // ---- 4. arms (a)-(e): where the scan's time and memory actually go -----------------------------

    /**
     * The cost attribution proper: every arm run once on the real book with wall-clock, Java-heap
     * delta and process-PSS delta recorded, plus the per-rule detection counts H1's predicted ratio
     * needs. Nothing here is asserted against a latency; the assertions are the same equivalence
     * checks that make the numbers mean something.
     *
     * Arm (b) is measured BOTH before and after arm (a), and arms (c)/(d)/(e) are each read twice.
     * If the paired readings agree, the ordering is not carrying the result; if they do not, that is
     * itself the finding and it is in the log. Arm (a)'s own second reading is the one
     * [armsAgreeOnHeadings] takes earlier in the same class run.
     *
     * **A stated asymmetry between arms (a) and (b)** (Gate-4 Medium): the shipped call compiles its
     * `Regex` INSIDE the timed region and performs coroutine cancellation checks, while `walkReused`
     * receives a precompiled `Pattern` and omits them. Rather than hide that, the compile cost is
     * measured separately and reported (`compile_ns_per_call`), so a reader can correct for it — it
     * matters little against a multi-second baseline but would matter a great deal if the two arms
     * ever collapse to the same order of magnitude.
     */
    @Test
    fun reportsCostAttribution() {
        val text = requireRealBookText()
        val rule = requireWinningRule(text)
        val pattern = compileWinning(rule)
        warmUpWalks(text, pattern, rule)

        val reusedFirst = arm("b1-reused-matcher-before-baseline") { walkReused(text, pattern, SCAN_LIMIT) }
        val shipped = arm("a-shipped-extractHeadings") {
            runBlocking { TxtTocRuleEngine.extractHeadings(text, rule, SCAN_LIMIT) }
        }
        val reusedSecond = arm("b2-reused-matcher-after-baseline") { walkReused(text, pattern, SCAN_LIMIT) }
        val findOnly = arm("c1-find-only") { countReused(text, pattern) }
        val findOnly2 = arm("c2-find-only") { countReused(text, pattern) }
        val lineStarts = arm("d1-line-start-enumeration") { countLineStarts(text) }
        val lineStarts2 = arm("d2-line-start-enumeration") { countLineStarts(text) }
        val detection = arm("e1-detectBestRule-shipped") { runBlocking { TxtTocRuleEngine.detectBestRule(text) } }
        val detection2 = arm("e2-detectBestRule-shipped") { runBlocking { TxtTocRuleEngine.detectBestRule(text) } }

        // Price arm (a)'s in-band pattern compilation, which arm (b) does not pay.
        repeat(COMPILE_SAMPLES) { objectSink = Pattern.compile(rule.pattern, Pattern.MULTILINE) }
        val compileStart = System.nanoTime()
        repeat(COMPILE_SAMPLES) {
            objectSink = Pattern.compile(rule.pattern, Pattern.MULTILINE)
            sinkWrites++
        }
        val compileNsPerCall = (System.nanoTime() - compileStart).toDouble() / COMPILE_SAMPLES

        // Arm (e)'s second half: what every enabled rule finds in the sample. Under H1 the number of
        // Matchers detection constructs is (enabled rules + total matches), which is what turns the
        // predicted extraction:detection ratio from a range into a number. Counts are walk-invariant
        // (pinned by armsAgreeOnHeadings), so the cheap reused walk is used to gather them.
        val sample = sampleOf(text)
        var totalDetectionMatches = 0
        var bestRuleId = -1
        var bestCount = 0
        val perRule = StringBuilder()
        TxtTocRules.defaults.filter { it.enabled }.forEach { r ->
            val p = runCatching { Pattern.compile(r.pattern, Pattern.MULTILINE) }.getOrNull() ?: return@forEach
            val t0 = SystemClock.elapsedRealtime()
            val c = countReused(sample, p)
            val ms = SystemClock.elapsedRealtime() - t0
            totalDetectionMatches += c
            if (c > bestCount) {
                bestCount = c
                bestRuleId = r.id
            }
            perRule.append(" rule").append(r.id).append('=').append(c).append('@').append(ms).append("ms")
        }

        report(
            "COST-SUMMARY chars_utf16=${text.length} headings=${shipped.value.headings.size} " +
                "a_shipped_ms=${shipped.ms} b1_reused_ms=${reusedFirst.ms} b2_reused_ms=${reusedSecond.ms} " +
                "c_find_only_ms=${findOnly.ms}/${findOnly2.ms} " +
                "d_line_starts_ms=${lineStarts.ms}/${lineStarts2.ms} " +
                "e_detect_ms=${detection.ms}/${detection2.ms} line_starts=${lineStarts.value} " +
                "compile_ns_per_call=${fmt(compileNsPerCall)} " +
                "sample_chars=${sample.length} detection_total_matches=$totalDetectionMatches " +
                "per_rule[$perRule ]",
        )
        report(
            "COST-MEMORY heap_delta_kb a=${shipped.heapDeltaKb} b1=${reusedFirst.heapDeltaKb} " +
                "b2=${reusedSecond.heapDeltaKb} c=${findOnly.heapDeltaKb}/${findOnly2.heapDeltaKb} " +
                "d=${lineStarts.heapDeltaKb}/${lineStarts2.heapDeltaKb} " +
                "e=${detection.heapDeltaKb}/${detection2.heapDeltaKb} | pss_delta_kb " +
                "a=${shipped.pssDeltaKb} b1=${reusedFirst.pssDeltaKb} b2=${reusedSecond.pssDeltaKb} " +
                "c=${findOnly.pssDeltaKb}/${findOnly2.pssDeltaKb} " +
                "d=${lineStarts.pssDeltaKb}/${lineStarts2.pssDeltaKb} " +
                "e=${detection.pssDeltaKb}/${detection2.pssDeltaKb}",
        )

        assertEquals(
            "the baseline arm must still find every chapter",
            EXPECTED_HEADINGS, shipped.value.headings.size,
        )
        assertEquals(
            "both reused-Matcher readings must find the same headings as the baseline",
            shipped.value.headings.size, reusedFirst.value.headings.size,
        )
        assertEquals(
            "the second reused reading must agree with the first",
            reusedFirst.value.headings.size, reusedSecond.value.headings.size,
        )
        assertEquals("arm (c) must see the same matches", reusedFirst.value.rawMatches, findOnly.value)
        assertEquals("arm (c)'s two readings must agree", findOnly.value, findOnly2.value)
        assertEquals("arm (d)'s two readings must agree", lineStarts.value, lineStarts2.value)
        assertEquals(
            "arm (e)'s two readings must pick the same rule",
            requireNotNull(detection.value).id, requireNotNull(detection2.value).id,
        )
        assertEquals(
            "the per-rule instrumentation must agree with the shipped detector's winner",
            requireNotNull(detection.value).id, bestRuleId,
        )
        assertTrue(
            "arm (d) must enumerate more line starts than there are headings — a heading sits on a line",
            lineStarts.value > EXPECTED_HEADINGS,
        )
        assertTrue("detection must have found matches to count", totalDetectionMatches > 0)
    }

    // ---- 5. arm (g): the length-proportionality test ------------------------------------------------

    /**
     * Arm (g) — **the decisive arm for H1.** Construct `pattern.matcher(input)` N times and perform
     * NO match, at THREE input sizes: the 7 M-char book, a 512 K-char prefix, and a 64-char prefix.
     *
     * **What is read, and why three sizes.** Two sizes give only a ratio, which can neither
     * establish flatness nor quantify scaling once measurement noise is in play (Gate-4 R1 High).
     * Three let each model be tested against a HELD-OUT point: the length-proportional model is
     * fitted from the outer two and must then predict the middle one, while the constant-cost model
     * predicts all three are equal. The report carries the raw per-construction cost at each size,
     * the raw long/short ratio, the fitted per-character marginal cost, and the mid-point's
     * predicted-vs-observed error — so the reading rests on RAW paired measurements rather than on a
     * subtraction. The overhead-corrected figures are logged too, but they are secondary precisely
     * because a subtraction is least trustworthy in the flat case, which is the case that would kill
     * H1.
     *
     * **What this arm does and does not establish** (Gate-4 R2 Medium). It samples three sizes on
     * one device with one pattern; it has no variance estimate and no pre-registered acceptance
     * threshold for "equal" or "linear". A length-proportional implementation could still miss the
     * held-out point through fixed costs or cache effects, and some non-proportional function could
     * happen to fit three points. So this is strong EVIDENCE that the cost is proportional to input
     * length over the sampled range — not a proof of asymptotic complexity. What it can do, and what
     * it exists for, is discriminate decisively between "roughly constant" and "roughly
     * proportional", which is exactly the fork H1 turns on.
     *
     * **Ordering.** All three sizes are measured twice, the second round in reverse order, so JIT
     * tier, allocator state and thermal drift show up as a discrepancy between rounds rather than as
     * a result. **Escape.** Each constructed `Matcher` is published to the `@Volatile` [matcherSink]
     * inside the timed loop — a real reference escape, not merely an identity hash — so ART cannot
     * scalar-replace it and report a spuriously flat cost. **Memory.** The timed work is broken into
     * batches with an untimed collection between them, capping live input attachments well below the
     * level at which the `lowmemorykiller` has already taken this app once.
     *
     * Asserted: only that the arm did work and that the sink was genuinely written. A latency
     * assertion here would be a benchmark gating on the number it exists to discover.
     */
    @Test
    fun reportsMatcherConstructionCost() {
        val text = requireRealBookText()
        val rule = requireWinningRule(text)
        val pattern = compileWinning(rule)
        val sizes = listOf(
            "long" to text,
            "mid" to safePrefix(text, MID_TEXT_CHARS),
            "short" to safePrefix(text, SHORT_TEXT_CHARS),
        )
        val overheadNs = measureSinkOverhead()
        val round1 = sizes.associate { (name, input) ->
            name to measureConstructionCost("$name-round1", pattern, input)
        }
        val round2 = sizes.reversed().associate { (name, input) ->
            name to measureConstructionCost("$name-round2", pattern, input)
        }

        listOf("round1" to round1, "round2" to round2).forEach { (round, r) ->
            val long = requireNotNull(r["long"])
            val mid = requireNotNull(r["mid"])
            val short = requireNotNull(r["short"])
            // The O(n) model, fitted from the OUTER two points only, then tested on the middle one.
            val marginalNsPerChar =
                (long.rawNsPer - short.rawNsPer) / (long.textChars - short.textChars).toDouble()
            val predictedMid = short.rawNsPer + marginalNsPerChar * (mid.textChars - short.textChars)
            val midErrorPct =
                if (mid.rawNsPer > 0) 100.0 * (predictedMid - mid.rawNsPer) / mid.rawNsPer else Double.NaN
            report(
                "ARM-G $round sink_overhead_ns_per_iter=${fmt(overheadNs)} " +
                    listOf(long, mid, short).joinToString(" ") { c ->
                        "${c.label}[chars=${c.textChars} n=${c.count} batches=${c.batches} " +
                            "total_ns=${c.totalNs} raw_ns_per=${fmt(c.rawNsPer)} " +
                            "net_ns_per=${fmt(c.netNsPer(overheadNs))} settled=${c.settled}]"
                    } +
                    " raw_long_over_short=${"%.2f".format(long.rawNsPer / short.rawNsPer)}" +
                    " net_long_over_short=${"%.2f".format(long.netNsPer(overheadNs) / short.netNsPer(overheadNs))}" +
                    " fitted_marginal_ns_per_char=${"%.4f".format(marginalNsPerChar)}" +
                    " mid_predicted_ns=${fmt(predictedMid)} mid_observed_ns=${fmt(mid.rawNsPer)}" +
                    " mid_prediction_error_pct=${"%.1f".format(midErrorPct)}",
            )
        }

        val measured = round1.values + round2.values
        measured.forEach { c ->
            assertTrue("arm (g) sub-measurement ${c.label} must have constructed Matchers", c.count > 0)
            assertTrue("arm (g) sub-measurement ${c.label} must be measurable (>0 ns)", c.totalNs > 0)
            assertTrue(
                "arm (g) sub-measurement ${c.label} must have published a constructed Matcher to the " +
                    "volatile sink inside a TIMED batch — a loop that could be optimised away is not " +
                    "evidence",
                c.escaped,
            )
            // EXACT, not circumstantial (Gate-4 R2 Medium): one sink write per timed construction,
            // counted over the timed regions alone — warm-up, probe and the overhead loop excluded.
            assertEquals(
                "arm (g) sub-measurement ${c.label} must have written the sink exactly once per " +
                    "timed construction",
                c.count.toLong(), c.timedWrites,
            )
        }
    }

    /** A prefix of [text] that never splits a surrogate pair (the [sampleOf] rule, generalised). */
    private fun safePrefix(text: String, chars: Int): String {
        if (text.length <= chars) return text
        var end = chars
        if (text[end - 1].isHighSurrogate() && text[end].isLowSurrogate()) end--
        return text.substring(0, end)
    }

    private class ConstructionCost(
        val label: String,
        val textChars: Int,
        val count: Int,
        val batches: Int,
        val totalNs: Long,
        /** Did this size need an inter-batch collection (i.e. was it attaching real memory)? */
        val settled: Boolean,
        /**
         * Was the volatile sink non-null at the end of a timed batch? The sink is cleared before the
         * first timed batch, so this can only be true if a TIMED construction published to it.
         */
        val escaped: Boolean,
        /** Sink writes inside the timed regions ONLY — excludes warm-up, probe and the overhead loop. */
        val timedWrites: Long,
    ) {
        val rawNsPer = totalNs.toDouble() / count
        fun netNsPer(overheadNsPerIter: Double) = (rawNsPer - overheadNsPerIter).coerceAtLeast(0.0)
    }

    /**
     * The floor for arm (g): the same loop shape and the same volatile reference-sink write, with a
     * trivial allocation in place of the `Matcher`.
     *
     * It is a FLOOR, not an exact subtraction — a bare `Object`'s allocation is cheaper than a
     * `Matcher`'s — which is exactly why the arm's verdict is read from the RAW per-construction
     * costs and this figure is reported only as a secondary correction (Gate-4 High).
     */
    private fun measureSinkOverhead(): Double {
        repeat(WARMUP_CONSTRUCTIONS) {
            objectSink = Any()
            sinkWrites++
        }
        gcSettle()
        val n = MAX_CONSTRUCTIONS
        val t0 = System.nanoTime()
        repeat(n) {
            objectSink = Any()
            sinkWrites++
        }
        return (System.nanoTime() - t0).toDouble() / n
    }

    /**
     * N × `pattern.matcher(input)` with no matching, timed in batches.
     *
     * Batching exists ONLY to bound live native input attachments: the collection between batches is
     * OUTSIDE every timed region, and the reported total is the sum of the timed regions, so the
     * measurement is unaffected by it. The probe that chooses the iteration count is likewise a
     * memory-sizing device, never an input to the reported number.
     */
    private fun measureConstructionCost(label: String, pattern: Pattern, input: String): ConstructionCost {
        repeat(WARMUP_CONSTRUCTIONS) {
            matcherSink = pattern.matcher(input)
            sinkWrites++
        }
        gcSettle()

        // Sizing probe — it chooses HOW MANY iterations to average, never the reported per-iteration
        // number (see TARGET_TIMED_NS). A noisy probe costs precision, not correctness.
        val probeStart = System.nanoTime()
        repeat(PROBE_CONSTRUCTIONS) {
            matcherSink = pattern.matcher(input)
            sinkWrites++
        }
        val probeNsPer = (System.nanoTime() - probeStart).toDouble() / PROBE_CONSTRUCTIONS
        val cap = (TARGET_TIMED_NS / probeNsPer)
            .toLong()
            .coerceIn(MIN_CONSTRUCTIONS.toLong(), MAX_CONSTRUCTIONS.toLong())
            .toInt()
        val attachBytes = 2L * maxOf(1, input.length)
        val batchSize = (BATCH_ATTACH_BYTES / attachBytes).coerceIn(1L, cap.toLong()).toInt()
        val settleBetweenBatches = attachBytes * batchSize >= SETTLE_ATTACH_BYTES
        report(
            "ARM-G-PROBE $label probe_ns_per=${fmt(probeNsPer)} planned_n=$cap batch=$batchSize " +
                "settle_between_batches=$settleBetweenBatches",
        )
        gcSettle()

        // Clear the sink BEFORE the timed batches so the `escaped` observation below can only be
        // satisfied by a TIMED write — warm-up and probe writes would otherwise leave it non-null
        // and the check would pass without proving anything (Gate-4 R2 Medium).
        matcherSink = null
        val writesAtTimedStart = sinkWrites

        val deadline = SystemClock.elapsedRealtime() + TIME_BUDGET_MS
        var count = 0
        var batches = 0
        var totalNs = 0L
        var escaped = false
        while (count < cap) {
            val n = minOf(batchSize, cap - count)
            val t0 = System.nanoTime()
            var i = 0
            while (i < n) {
                matcherSink = pattern.matcher(input)
                sinkWrites++
                i++
                if ((i and BUDGET_CHECK_MASK) == 0 && SystemClock.elapsedRealtime() > deadline) break
            }
            totalNs += System.nanoTime() - t0
            count += i
            batches++
            // Read the escape BEFORE clearing it: this is the observation that proves a constructed
            // Matcher really was published to the volatile field rather than optimised away.
            escaped = escaped || matcherSink != null
            if (settleBetweenBatches) {
                // UNTIMED: release this batch's attachments before the next one allocates its own.
                matcherSink = null
                System.gc()
                Thread.sleep(BATCH_SETTLE_MS)
            }
            if (SystemClock.elapsedRealtime() > deadline) break
        }
        return ConstructionCost(
            label = label,
            textChars = input.length,
            count = count,
            batches = batches,
            totalNs = totalNs,
            settled = settleBetweenBatches,
            escaped = escaped,
            timedWrites = sinkWrites - writesAtTimedStart,
        )
    }
}
