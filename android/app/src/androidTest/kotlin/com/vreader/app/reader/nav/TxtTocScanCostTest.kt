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
 * | (g) | N × `pattern.matcher(text)` with NO matching, at two text sizes — **the H1 falsifier** |
 * | (h) | the same K matches walked three ways — separates construction cost from `find(int)`'s `reset()` |
 * | (f) | target-semantic logging: bare `\d`/`\s` vs the repaired classes on the real engine |
 *
 * A flat arm (g) kills H1 and sends WI-2 back to planning. An arm (h) that attributes the cost to
 * `reset()` rather than to construction changes what WI-2 should fix. Both outcomes are named in
 * the plan in advance so neither can be explained away afterwards.
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
 *  - *Ordering*: arm (b) is measured both BEFORE and AFTER arm (a), and arm (h)'s trio is run twice
 *    in opposite orders. An ordering effect therefore shows up as a discrepancy rather than hiding.
 *  - *GC timing*: [gcSettle] runs before every timed region, and the "after" memory sample is taken
 *    WITHOUT a collection, so retained native growth is visible instead of being swept away.
 *  - *Dead-code elimination* (plan §4.3, Gate-2 R2 HIGH): a constructed `Matcher` that is never used
 *    could be scalar-replaced by ART's JIT, reporting a spuriously flat cost and FALSELY KILLING
 *    H1 — the expensive wrong answer, since it would send a correct fix back to planning. Every
 *    construction in arm (g) therefore escapes into the `@Volatile` [constructionSink] *inside* the
 *    timed loop, and the loop+sink overhead is measured separately and reported so the net figure is
 *    honest. The sink performs no match operation, so the arm still isolates construction.
 *
 * **Memory is a measured output, not a claim** (plan §4.5). Each arm records the Java-heap delta and
 * the process-PSS delta around a single pass. The plan commits three readings in advance: materially
 * lower growth in the reused-`Matcher` arm means the same root cause; comparable growth means it is
 * not the scan; too noisy means say exactly that and record the noise floor.
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
     * The non-elidable sink for arm (g). `@Volatile` so ART cannot prove a constructed `Matcher`
     * dead and scalar-replace it, which would report a flat construction cost and falsely kill H1.
     */
    @Volatile
    private var constructionSink: Int = 0

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

        /** Arm (h): how many matches each of the three walks performs. */
        const val WALK_MATCHES = 200

        /** Arm (h)'s warm-up walk length — enough to JIT the three shapes, small enough to be free. */
        const val WARMUP_MATCHES = 20

        /** Arms (a)/(b)/(c) warm-up prefix: big enough to JIT the walks, small enough to be free. */
        const val WARMUP_PREFIX_CHARS = 512 * 1024

        /** Arm (g) — untimed constructions that JIT the path before anything is measured. */
        const val WARMUP_CONSTRUCTIONS = 32

        /** Arm (g) — a short timed probe used ONLY to size the real loop (see [EXPENSIVE_NS]). */
        const val PROBE_CONSTRUCTIONS = 32

        /**
         * Arm (g) sizing. A genuinely O(1) construction costs well under 1 µs; an O(n) construction
         * over 7 M chars costs milliseconds. Three orders of magnitude separate them, so 5 µs is a
         * safe classifier — and it exists purely to bound MEMORY: under H1 each construction pins a
         * ~14 MB native buffer released only on a Java collection, so a 300 000-iteration loop would
         * generate terabytes of native traffic and be lowmemorykiller-ed before reporting anything.
         * The classification is logged; the verdict is read from the per-construction cost, which is
         * valid whichever branch was taken.
         */
        const val EXPENSIVE_NS = 5_000.0
        const val EXPENSIVE_CONSTRUCTIONS = 200
        const val CHEAP_CONSTRUCTIONS = 300_000
        const val TIME_BUDGET_MS = 3_000L

        /** How often the timed construction loop checks its wall-clock budget (a power-of-two mask). */
        const val BUDGET_CHECK_MASK = 0x3F

        /** Arm (g)'s second text size. Short enough that O(n) work over it is unmeasurable. */
        const val SHORT_TEXT_CHARS = 64

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

    /** Emit to logcat AND to internal storage, which the connected task does not wipe. */
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
     * Arm (h) — the same K matches walked three ways over the same text, so the scanning work is
     * identical and only the per-match ceremony differs:
     *
     *  - **h1** one `Matcher`, K × no-arg `find()` — the pure walk.
     *  - **h2** one `Matcher`, K × `find(resume_i)` — the walk plus K `reset()`s, no construction.
     *  - **h3** K fresh `Matcher`s, each `find(resume_i)` — the walk plus K `reset()`s plus K
     *    constructions. This is exactly what Kotlin's `MatchResult.next()` does.
     *
     * `resume_i` is the position `next()` itself would resume from (the previous match's end, +1
     * after an empty match), so all three scan the same gaps rather than one of them starting
     * conveniently on top of its match. Therefore `h2 − h1` is K resets and `h3 − h2` is K
     * constructions — a direct split that arms (a)/(b) alone conflate, and a second, independent
     * estimate of the construction cost that arm (g) measures a different way.
     *
     * The trio runs twice in OPPOSITE orders; an ordering or JIT effect shows up as a discrepancy
     * between the rounds instead of masquerading as a result.
     */
    @Test
    fun reportsConstructionVsResetSplit() {
        val text = requireRealBookText()
        val rule = requireWinningRule(text)
        val pattern = compileWinning(rule)
        val resume = resumePositions(pattern, text, WALK_MATCHES)

        // Warm-up trio on a smaller K — untimed.
        val warmResume = resumePositions(pattern, text, WARMUP_MATCHES)
        walkNoArg(pattern, text, WARMUP_MATCHES)
        walkReusedFindFrom(pattern, text, warmResume)
        walkFreshFindFrom(pattern, text, warmResume)
        gcSettle()

        val r1h1 = timeWalk("h1-round1-reused-noarg-find") { walkNoArg(pattern, text, WALK_MATCHES) }
        val r1h2 = timeWalk("h2-round1-reused-find-from") { walkReusedFindFrom(pattern, text, resume) }
        val r1h3 = timeWalk("h3-round1-fresh-find-from") { walkFreshFindFrom(pattern, text, resume) }
        val r2h3 = timeWalk("h3-round2-fresh-find-from") { walkFreshFindFrom(pattern, text, resume) }
        val r2h2 = timeWalk("h2-round2-reused-find-from") { walkReusedFindFrom(pattern, text, resume) }
        val r2h1 = timeWalk("h1-round2-reused-noarg-find") { walkNoArg(pattern, text, WALK_MATCHES) }

        // The equivalence that makes the timings comparable: all six walks found the same matches.
        assertEquals("arm (h) must walk the requested number of matches", WALK_MATCHES, r1h1.second.size)
        listOf(
            "h2-round1" to r1h2, "h3-round1" to r1h3,
            "h3-round2" to r2h3, "h2-round2" to r2h2, "h1-round2" to r2h1,
        ).forEach { (name, walk) ->
            assertTrue(
                "$name must have found the SAME $WALK_MATCHES match offsets as h1-round1 — otherwise " +
                    "the three walks are not doing the same work and their times are not comparable",
                walk.second.contentEquals(r1h1.second),
            )
        }

        val resetNs1 = (r1h2.first - r1h1.first).toDouble() / WALK_MATCHES
        val constructNs1 = (r1h3.first - r1h2.first).toDouble() / WALK_MATCHES
        val resetNs2 = (r2h2.first - r2h1.first).toDouble() / WALK_MATCHES
        val constructNs2 = (r2h3.first - r2h2.first).toDouble() / WALK_MATCHES
        report(
            "ARM-H k=$WALK_MATCHES text_chars=${text.length} " +
                "round1_ns h1=${r1h1.first} h2=${r1h2.first} h3=${r1h3.first} " +
                "round2_ns h1=${r2h1.first} h2=${r2h2.first} h3=${r2h3.first} " +
                "reset_ns_per_op=${"%.1f".format(resetNs1)}/${"%.1f".format(resetNs2)} " +
                "construction_ns_per_op=${"%.1f".format(constructNs1)}/${"%.1f".format(constructNs2)}",
        )
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
     * Arm (b) is measured BOTH before and after arm (a). If the two readings agree, the ordering is
     * not carrying the result; if they do not, that is itself the finding and it is in the log.
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
        val findOnly = arm("c-find-only") { countReused(text, pattern) }
        val lineStarts = arm("d-line-start-enumeration") { countLineStarts(text) }
        val detection = arm("e-detectBestRule-shipped") { runBlocking { TxtTocRuleEngine.detectBestRule(text) } }

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
                "c_find_only_ms=${findOnly.ms} d_line_starts_ms=${lineStarts.ms} " +
                "e_detect_ms=${detection.ms} line_starts=${lineStarts.value} " +
                "sample_chars=${sample.length} detection_total_matches=$totalDetectionMatches " +
                "per_rule[$perRule ]",
        )
        report(
            "COST-MEMORY heap_delta_kb a=${shipped.heapDeltaKb} b1=${reusedFirst.heapDeltaKb} " +
                "b2=${reusedSecond.heapDeltaKb} c=${findOnly.heapDeltaKb} d=${lineStarts.heapDeltaKb} " +
                "e=${detection.heapDeltaKb} | pss_delta_kb a=${shipped.pssDeltaKb} " +
                "b1=${reusedFirst.pssDeltaKb} b2=${reusedSecond.pssDeltaKb} c=${findOnly.pssDeltaKb} " +
                "d=${lineStarts.pssDeltaKb} e=${detection.pssDeltaKb}",
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

    // ---- 5. arm (g): the H1 falsifier --------------------------------------------------------------

    /**
     * Arm (g) — **the falsifier.** Construct `pattern.matcher(input)` N times and perform NO match,
     * over the 7 M-char book and over a 64-char string. If construction is O(1) the per-construction
     * cost is the same at both sizes and H1 is DEAD; if it is O(n) the long-text cost scales with the
     * text and H1 stands. The **ratio of the two per-construction costs** is what is read, not either
     * absolute number.
     *
     * Every construction escapes into the `@Volatile` [constructionSink] inside the timed loop, so
     * ART cannot prove it dead — a scalar-replaced `Matcher` would report a flat cost and falsely
     * kill H1, which is the one wrong answer that would cost a correct fix. The loop-plus-sink
     * overhead is measured in the same shape and reported alongside, so the net per-construction
     * figure is not inflated by the machinery that makes the arm valid. That overhead is a constant
     * added to BOTH text sizes, so it biases the ratio toward 1 — i.e. toward killing H1, the
     * conservative direction for a hypothesis this plan wants falsified rather than flattered.
     *
     * Asserted: only that the arm did work and that the sink was written. A latency assertion here
     * would be a benchmark gating on the number it exists to discover.
     */
    @Test
    fun reportsMatcherConstructionCost() {
        val text = requireRealBookText()
        val rule = requireWinningRule(text)
        val pattern = compileWinning(rule)
        val shortText = text.substring(0, SHORT_TEXT_CHARS)

        val overheadNs = measureSinkOverhead()
        val long = measureConstructionCost("long", pattern, text, overheadNs)
        val short = measureConstructionCost("short", pattern, shortText, overheadNs)

        val ratio = if (short.netNsPer > 0) long.netNsPer / short.netNsPer else Double.NaN
        report(
            "ARM-G sink_overhead_ns_per_iter=${"%.1f".format(overheadNs)} " +
                "long_chars=${text.length} long_n=${long.count} long_total_ns=${long.totalNs} " +
                "long_raw_ns_per=${"%.1f".format(long.rawNsPer)} long_net_ns_per=${"%.1f".format(long.netNsPer)} " +
                "long_classified=${long.classification} " +
                "short_chars=${shortText.length} short_n=${short.count} short_total_ns=${short.totalNs} " +
                "short_raw_ns_per=${"%.1f".format(short.rawNsPer)} short_net_ns_per=${"%.1f".format(short.netNsPer)} " +
                "short_classified=${short.classification} " +
                "long_over_short_ratio=${"%.2f".format(ratio)} sink=$constructionSink",
        )

        assertTrue("arm (g) must have constructed Matchers over the long text", long.count > 0)
        assertTrue("arm (g) must have constructed Matchers over the short text", short.count > 0)
        assertTrue("arm (g)'s timed regions must be measurable (>0 ns)", long.totalNs > 0 && short.totalNs > 0)
        assertTrue(
            "the non-elidable sink must have been written — an unwritten sink means the arm could " +
                "have been optimised away and its result would not be evidence",
            constructionSink != 0,
        )
    }

    private class ConstructionCost(
        val count: Int,
        val totalNs: Long,
        val classification: String,
        overheadNsPerIter: Double,
    ) {
        val rawNsPer = totalNs.toDouble() / count
        val netNsPer = (rawNsPer - overheadNsPerIter).coerceAtLeast(0.0)
    }

    /**
     * The floor for arm (g): the same loop shape and the same volatile-sink write, with a trivial
     * allocation in place of the `Matcher`. Reported so the construction figure can be read net of
     * the machinery that makes it non-elidable. It is a FLOOR, not an exact subtraction — a fresh
     * `Object`'s identity hash is cheaper to install than a larger object's — so both the raw and
     * the net per-construction figures are logged and the raw one is the conservative reading.
     */
    private fun measureSinkOverhead(): Double {
        repeat(WARMUP_CONSTRUCTIONS) { constructionSink += System.identityHashCode(Any()) }
        gcSettle()
        val n = CHEAP_CONSTRUCTIONS
        val t0 = System.nanoTime()
        repeat(n) { constructionSink += System.identityHashCode(Any()) }
        return (System.nanoTime() - t0).toDouble() / n
    }

    private fun measureConstructionCost(
        label: String,
        pattern: Pattern,
        input: String,
        overheadNsPerIter: Double,
    ): ConstructionCost {
        repeat(WARMUP_CONSTRUCTIONS) { constructionSink += System.identityHashCode(pattern.matcher(input)) }
        gcSettle()

        // Sizing probe — memory safety only, never the reported number (see EXPENSIVE_NS).
        val probeStart = System.nanoTime()
        repeat(PROBE_CONSTRUCTIONS) { constructionSink += System.identityHashCode(pattern.matcher(input)) }
        val probeNsPer = (System.nanoTime() - probeStart).toDouble() / PROBE_CONSTRUCTIONS
        val expensive = probeNsPer > EXPENSIVE_NS
        report("ARM-G-PROBE $label probe_ns_per=${"%.1f".format(probeNsPer)} expensive=$expensive")
        gcSettle()

        val cap = if (expensive) EXPENSIVE_CONSTRUCTIONS else CHEAP_CONSTRUCTIONS
        val deadline = SystemClock.elapsedRealtime() + TIME_BUDGET_MS
        var count = 0
        val t0 = System.nanoTime()
        while (count < cap) {
            constructionSink += System.identityHashCode(pattern.matcher(input))
            count++
            if ((count and BUDGET_CHECK_MASK) == 0 && SystemClock.elapsedRealtime() > deadline) break
        }
        val totalNs = System.nanoTime() - t0
        return ConstructionCost(
            count = count,
            totalNs = totalNs,
            classification = if (expensive) "expensive" else "cheap",
            overheadNsPerIter = overheadNsPerIter,
        )
    }
}
