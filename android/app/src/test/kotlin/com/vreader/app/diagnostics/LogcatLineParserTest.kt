package com.vreader.app.diagnostics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Feature #164 WI-1 — exhaustive tests for the PURE half of the logcat source.
 *
 * Every "tolerates" case below asserts a SPECIFIED expected output rather than merely
 * "does not throw": a test that only asserts absence of a crash passes under any behavior,
 * including the behavior that silently drops every row (which would degrade the whole
 * feature to the ring buffer with no error).
 *
 * Input shape is `logcat -d -v uid -v threadtime -v year -v UTC`, sampled verbatim from
 * emulator-5554 (API 35):
 *
 *     2026-08-04 19:26:12.114 +0000  1000   572   718 W BestClock: java.time.DateTimeException: ...
 *     2026-08-04 19:26:13.503 +0000  wifi   796   796 I wpa_supplicant: wlan0: CTRL-EVENT-BEACON-LOSS
 *
 * Note the third line above: the uid column is NOT always numeric even for system rows, so
 * a parser that assumes `\d+` is already wrong before app uids enter the picture.
 */
class LogcatLineParserTest {

    private val ownUid = 10209
    private val foreignUid = 10042

    /** `2026-08-04T19:26:12.114Z` — computed independently of the implementation. */
    private val goldenMillis = 1785871572114L

    private fun line(
        date: String = "2026-08-04",
        time: String = "19:26:12.114",
        zone: String = "+0000",
        uid: String = "10209",
        pid: String = "3312",
        tid: String = "3312",
        level: String = "W",
        rest: String,
    ) = "$date $time $zone  $uid  $pid  $tid $level $rest"

    private fun parse(vararg lines: String) =
        LogcatLineParser.parse(lines.asSequence(), ownUid)

    // ---------------------------------------------------------------- golden line

    @Test
    fun parsesGoldenLineIntoEveryField() {
        val entries = parse(line(rest = "Library: imported 3 books"))
        assertEquals(1, entries.size)
        val e = entries.single()
        assertEquals(goldenMillis, e.timeMillis)
        assertEquals(DiagnosticsLevel.WARN, e.level)
        assertEquals("Library", e.category)
        assertEquals("imported 3 books", e.message)
        assertNull(e.sequenceId)
    }

    @Test
    fun honoursTheLinesOwnUtcOffsetRatherThanAnAmbientZone() {
        val utc = parse(line(date = "2026-01-02", time = "03:04:05.006", zone = "+0000",
            rest = "Sync: a")).single()
        val east = parse(line(date = "2026-01-02", time = "03:04:05.006", zone = "+0200",
            rest = "Sync: a")).single()
        assertEquals(1767323045006L, utc.timeMillis)
        assertEquals(1767315845006L, east.timeMillis)
    }

    @Test
    fun parsesEveryEmittableLevel() {
        val levels = listOf(
            "V" to DiagnosticsLevel.VERBOSE, "D" to DiagnosticsLevel.DEBUG,
            "I" to DiagnosticsLevel.INFO, "W" to DiagnosticsLevel.WARN,
            "E" to DiagnosticsLevel.ERROR, "F" to DiagnosticsLevel.ASSERT,
        )
        levels.forEach { (char, expected) ->
            assertEquals(expected, parse(line(level = char, rest = "T: m")).single().level)
        }
    }

    @Test
    fun preservesEntryOrderOldestToNewest() {
        val entries = parse(
            line(time = "19:26:12.114", rest = "T: first"),
            line(time = "19:26:13.114", rest = "T: second"),
            line(time = "19:26:14.114", rest = "T: third"),
        )
        assertEquals(listOf("first", "second", "third"), entries.map { it.message })
    }

    // ------------------------------------------------------------- uid rendering

    @Test
    fun acceptsNumericUidRendering() {
        assertEquals(1, parse(line(uid = "10209", rest = "T: m")).size)
    }

    @Test
    fun acceptsSymbolicUidRendering() {
        // u0_a209 == 0 * 100000 + 10000 + 209 == 10209
        assertEquals(1, parse(line(uid = "u0_a209", rest = "T: m")).size)
    }

    @Test
    fun symbolicUidHonoursTheUserId() {
        // Secondary user 11: uid == 11 * 100000 + 10000 + 209 == 1110209.
        val secondary = LogcatLineParser.parse(
            sequenceOf(line(uid = "u11_a209", rest = "T: m")), ownUid = 1_110_209
        )
        assertEquals(1, secondary.size)
        // The SAME line must NOT match user 0's uid — otherwise a work-profile row would
        // leak into the primary user's diagnostics.
        assertEquals(0, parse(line(uid = "u11_a209", rest = "T: m")).size)
    }

    @Test
    fun dropsRowsFromOtherUids() {
        val entries = parse(
            line(uid = "10209", rest = "Mine: keep"),
            line(uid = "10042", rest = "Theirs: drop"),
            line(uid = "u0_a42", rest = "Theirs: drop"),
            line(uid = "1000", rest = "System: drop"),
            line(uid = "wifi", rest = "wpa_supplicant: drop"),
            line(uid = "root", rest = "Kernel: drop"),
        )
        assertEquals(listOf("keep"), entries.map { it.message })
    }

    @Test
    fun dropsEverythingWhenNoRowBelongsToUs() {
        val entries = LogcatLineParser.parse(
            sequenceOf(line(uid = "10209", rest = "Mine: m")), ownUid = foreignUid
        )
        assertTrue(entries.isEmpty())
    }

    @Test
    fun ignoresMalformedSymbolicUidTokens() {
        listOf("u_a209", "u0_a", "ua209", "u0a209", "u0_a209x", "u0_i209").forEach { token ->
            assertEquals("token $token must not match", 0, parse(line(uid = token, rest = "T: m")).size)
        }
    }

    // -------------------------------------------------------- tag/message split

    @Test
    fun firstColonSpaceAfterTheLevelTerminatesTheTag() {
        val e = parse(line(rest = "Reader: java.lang.IllegalStateException: boom")).single()
        assertEquals("Reader", e.category)
        assertEquals("java.lang.IllegalStateException: boom", e.message)
    }

    @Test
    fun tagContainingAColonSurvivesWhenNotFollowedByASpace() {
        val e = parse(line(rest = "Foo:Bar: hello")).single()
        assertEquals("Foo:Bar", e.category)
        assertEquals("hello", e.message)
    }

    @Test
    fun tagContainingSpacesIsKeptWhole() {
        val e = parse(line(rest = "My Tag: hello")).single()
        assertEquals("My Tag", e.category)
        assertEquals("hello", e.message)
    }

    @Test
    fun tagContainingColonSpaceSplitsAtTheFirstOccurrence() {
        // Genuinely ambiguous input: the RULE (first ": " wins) is what is asserted, so this
        // fixture cannot pass under an arbitrary alternative behavior.
        val e = parse(line(rest = "Foo: Bar: hello")).single()
        assertEquals("Foo", e.category)
        assertEquals("Bar: hello", e.message)
    }

    @Test
    fun emptyTagYieldsEmptyCategoryAndIntactMessage() {
        val e = parse(line(rest = ": orphaned message")).single()
        assertEquals("", e.category)
        assertEquals("orphaned message", e.message)
    }

    @Test
    fun emptyMessageWithTrailingSeparatorSpace() {
        val e = parse(line(rest = "Library: ")).single()
        assertEquals("Library", e.category)
        assertEquals("", e.message)
    }

    @Test
    fun emptyMessageWithoutTrailingSeparatorSpace() {
        // Some pipelines strip trailing whitespace, leaving "Tag:" with no ": ".
        val e = parse(line(rest = "Library:")).single()
        assertEquals("Library", e.category)
        assertEquals("", e.message)
    }

    @Test
    fun remainderWithNoColonAtAllKeepsTheTextAsMessage() {
        val e = parse(line(rest = "no separator here")).single()
        assertEquals("", e.category)
        assertEquals("no separator here", e.message)
    }

    // ----------------------------------------------------------------- markers

    @Test
    fun leadingMarkerIsParsedIntoSequenceIdAndStripped() {
        val e = parse(line(rest = "Library: ${VLogMarker.encode(42)}imported 3 books")).single()
        assertEquals(42L, e.sequenceId)
        assertEquals("imported 3 books", e.message)
    }

    @Test
    fun markerWithZeroAndLargeIdsRoundTrip() {
        assertEquals(0L, parse(line(rest = "T: ${VLogMarker.encode(0)}m")).single().sequenceId)
        assertEquals(
            Long.MAX_VALUE,
            parse(line(rest = "T: ${VLogMarker.encode(Long.MAX_VALUE)}m")).single().sequenceId,
        )
    }

    @Test
    fun noMarkerYieldsNullSequenceIdAndUnchangedMessage() {
        val e = parse(line(rest = "T: plain message")).single()
        assertNull(e.sequenceId)
        assertEquals("plain message", e.message)
    }

    @Test
    fun malformedMarkersAreOrdinaryTextAndAreNotStripped() {
        listOf("«v»", "«vabc»", "«v12", "v12»", "«V12»", "«v-1»", "«v 12»").forEach { malformed ->
            val e = parse(line(rest = "T: ${malformed}tail")).single()
            assertNull("$malformed must not parse", e.sequenceId)
            assertEquals("${malformed}tail", e.message)
        }
    }

    @Test
    fun anIdThatOverflowsLongIsTreatedAsOrdinaryText() {
        val e = parse(line(rest = "T: «v99999999999999999999»tail")).single()
        assertNull(e.sequenceId)
        assertEquals("«v99999999999999999999»tail", e.message)
    }

    @Test
    fun markerIsOnlyRecognisedAtTheStartOfTheMessage() {
        val e = parse(line(rest = "T: prefix ${VLogMarker.encode(7)}tail")).single()
        assertNull(e.sequenceId)
        assertEquals("prefix «v7»tail", e.message)
    }

    @Test
    fun noEntryReachingTheStoreRetainsAMarker() {
        // The mixed fixture the acceptance criterion names: marked, unmarked, malformed,
        // a continuation carrying a marker-looking token, and a foreign-uid marked row.
        val entries = parse(
            line(rest = "Library: ${VLogMarker.encode(1)}first"),
            line(rest = "Reader: plain"),
            line(rest = "Sync: «v»malformed-is-text"),
            line(rest = "AI: ${VLogMarker.encode(2)}second"),
            "\tat com.vreader.app.Foo.bar(Foo.kt:12)",
            line(uid = "1000", rest = "System: ${VLogMarker.encode(3)}not ours"),
        )
        assertEquals(4, entries.size)
        // Declared independently of the implementation: no message that reaches the store may
        // still begin with a WELL-FORMED marker, whatever the parser thinks it did with it.
        val wellFormedMarker = Regex("^«v\\d+»")
        val stillMarked = entries.filter { wellFormedMarker.containsMatchIn(it.message) }
        assertTrue("no entry may retain a marker, found: $stillMarked", stillMarked.isEmpty())
        assertEquals(listOf(1L, null, null, 2L), entries.map { it.sequenceId })
        assertEquals(
            listOf("first", "plain", "«v»malformed-is-text", "second\n\tat com.vreader.app.Foo.bar(Foo.kt:12)"),
            entries.map { it.message },
        )
    }

    // ------------------------------------------------- dividers + continuations

    @Test
    fun skipsBufferDividerLines() {
        val entries = parse(
            "--------- beginning of main",
            line(rest = "T: a"),
            "--------- beginning of system",
            line(rest = "T: b"),
            "--------- beginning of crash",
            "--------- beginning of kernel",
            "--------- switch to main",
        )
        assertEquals(listOf("a", "b"), entries.map { it.message })
    }

    @Test
    fun aDividerEndsTheContinuationRunSoTrailingTextIsNotAppended() {
        val entries = parse(
            line(rest = "T: head"),
            "--------- beginning of system",
            "\tstray continuation with no owner",
        )
        assertEquals(listOf("head"), entries.map { it.message })
    }

    @Test
    fun appendsContinuationLinesToThePreviousEntry() {
        val entries = parse(
            line(rest = "Reader: java.lang.IllegalStateException: boom"),
            "\tat com.vreader.app.reader.Foo.bar(Foo.kt:12)",
            "\tat com.vreader.app.reader.Foo.baz(Foo.kt:34)",
        )
        assertEquals(1, entries.size)
        assertEquals(
            "java.lang.IllegalStateException: boom\n" +
                "\tat com.vreader.app.reader.Foo.bar(Foo.kt:12)\n" +
                "\tat com.vreader.app.reader.Foo.baz(Foo.kt:34)",
            entries.single().message,
        )
    }

    @Test
    fun discardsALeadingContinuationWithNoPredecessor() {
        val entries = parse(
            "\tat com.vreader.app.Orphan.method(Orphan.kt:1)",
            "Caused by: something with no header",
            line(rest = "T: real"),
        )
        assertEquals(listOf("real"), entries.map { it.message })
    }

    @Test
    fun doesNotAppendAContinuationThatFollowsAForeignUidRow() {
        // The dropped row's stack trace must not be grafted onto OUR previous entry — that
        // would leak another app's log text into our export.
        val entries = parse(
            line(rest = "Mine: ours"),
            line(uid = "1000", rest = "System: theirs"),
            "\tat com.other.app.Secret.leak(Secret.kt:1)",
        )
        assertEquals(1, entries.size)
        assertEquals("ours", entries.single().message)
    }

    @Test
    fun blankLinesNeitherCreateNorCorruptEntries() {
        val entries = parse(
            line(rest = "T: a"),
            "",
            "   ",
            line(rest = "T: b"),
        )
        assertEquals(listOf("a", "b"), entries.map { it.message })
    }

    // --------------------------------------------------------------- tolerance

    @Test
    fun emptyInputYieldsEmptyList() {
        assertEquals(emptyList<DiagnosticsLogEntry>(), LogcatLineParser.parse(emptySequence(), ownUid))
    }

    @Test
    fun cjkMessageRoundTripsExactly() {
        val cjk = "导入失败：《红楼梦》第一回 — 无法解析编码"
        val e = parse(line(rest = "Library: $cjk")).single()
        assertEquals(cjk, e.message)
        assertEquals("Library", e.category)
    }

    @Test
    fun cjkTagRoundTripsExactly() {
        val e = parse(line(rest = "图书馆: 已导入")).single()
        assertEquals("图书馆", e.category)
        assertEquals("已导入", e.message)
    }

    @Test
    fun messageAtTheLogdPayloadCapRoundTripsWhole() {
        val payload = "x".repeat(4068)
        val e = parse(line(rest = "T: $payload")).single()
        assertEquals(4068, e.message.length)
        assertEquals(payload, e.message)
    }

    @Test
    fun crlfLineEndingsAreStripped() {
        val entries = LogcatLineParser.parse(
            sequenceOf(
                "--------- beginning of main\r",
                line(rest = "Library: hello") + "\r",
                "\tat com.vreader.app.Foo.bar(Foo.kt:1)\r",
            ),
            ownUid,
        )
        assertEquals(1, entries.size)
        assertEquals("hello\n\tat com.vreader.app.Foo.bar(Foo.kt:1)", entries.single().message)
        assertEquals("Library", entries.single().category)
    }

    @Test
    fun aLineMissingTheZoneColumnStillParsesAsUtc() {
        // `-v UTC` is always passed, but a pipeline that drops the offset must not silently
        // shift timestamps into the ambient zone.
        val entries = LogcatLineParser.parse(
            sequenceOf("2026-08-04 19:26:12.114  10209  3312  3312 W Library: hello"),
            ownUid,
        )
        assertEquals(goldenMillis, entries.single().timeMillis)
    }

    @Test
    fun anImpossibleTimestampIsDiscardedRatherThanMisdated() {
        val entries = parse(
            line(date = "2026-13-45", rest = "T: bad"),
            line(rest = "T: good"),
        )
        assertEquals(listOf("good"), entries.map { it.message })
    }

    @Test
    fun endOfYearBoundaryParses() {
        val e = parse(line(date = "2026-12-31", time = "23:59:59.999", rest = "T: m")).single()
        assertEquals(1798761599999L, e.timeMillis)
    }

    @Test
    fun aLineThatIsNotAnEntryAtAllNeverBecomesAnEntry() {
        val entries = parse(
            "logcat: Unable to open log device '/dev/log/main': Permission denied",
            "beginning of /dev/log/main",
        )
        assertTrue(entries.isEmpty())
    }

    @Test
    fun toleratesWideColumnPaddingAndSingleSpaceColumns() {
        val padded = "2026-08-04 19:26:12.114 +0000    10209    3312    3312 W Library: hello"
        val tight = "2026-08-04 19:26:12.114 +0000 10209 3312 3312 W Library: hello"
        listOf(padded, tight).forEach { raw ->
            val e = LogcatLineParser.parse(sequenceOf(raw), ownUid).single()
            assertEquals("hello", e.message)
            assertEquals(goldenMillis, e.timeMillis)
        }
    }
}
