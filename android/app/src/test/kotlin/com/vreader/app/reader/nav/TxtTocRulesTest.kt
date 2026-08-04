package com.vreader.app.reader.nav

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Feature #139 WI-1 — [TxtTocRules]: the 25 TXT chapter-detection rules ported from iOS
 * (`vreader/Services/TXT/TXTTocRuleEngine.swift:142-350`, itself a Legado `txtTocRule.json` port).
 *
 * Two porting traps this suite exists to pin (plan §3.5), both **CJK-critical** and both
 * asserted over ALL 25 rules — including the 11 that ship disabled — so enabling a rule
 * later cannot resurrect a divergence:
 *
 * - **D1** — ICU (iOS) `\d` matches Unicode `Nd` (so full-width digits); `java.util.regex` `\d`
 *   is ASCII-only. Every `\d` becomes the explicit class [TxtTocRules.DIGIT].
 * - **D1b** — ICU `\s` covers `\p{Z}` (U+3000 IDEOGRAPHIC SPACE, NBSP, U+2028/29); Java's
 *   `\s` is `[ \t\n\x0B\f\r]`. Every whitespace position becomes [TxtTocRules.WS].
 *
 * Each divergence test carries its own **negative control**: the same pattern with the
 * widened class narrowed back to bare `\d` / `\s` must NOT match, proving the assertion is
 * load-bearing rather than vacuously true.
 *
 * Pure JVM — no Android runtime, no Robolectric.
 */
class TxtTocRulesTest {

    private companion object {
        /**
         * The two separators the D1b regression turns on, built from their CODE POINTS.
         *
         * Never write them as literal characters: Gate-2 rounds 3 and 4 each caught an NBSP
         * that copy-paste had silently normalized to an ASCII space, which turns a divergence
         * regression into a vacuous pass. An integer code point is pure ASCII in the source and
         * cannot be mangled by re-encoding.
         */
        val IDEO: String = Char(0x3000).toString() // IDEOGRAPHIC SPACE
        val NBSP: String = Char(0x00A0).toString() // NO-BREAK SPACE
    }

    private val rules: List<TxtTocRule> get() = TxtTocRules.defaults

    private fun compiled(rule: TxtTocRule) = Regex(rule.pattern, RegexOption.MULTILINE)

    /** The pattern with the leading indent class stripped — i.e. its non-indent body. */
    private fun body(rule: TxtTocRule) = rule.pattern.removePrefix("^${TxtTocRules.WS}{0,4}")

    /** Rules that reference the widened digit class (the D1 population), derived from the data. */
    private fun digitRules() = rules.filter { it.pattern.contains(TxtTocRules.DIGIT_CHARS) }

    /** Rules with a whitespace position beyond the leading indent (the D1b population). */
    private fun whitespaceRules() = rules.filter { body(it).contains(TxtTocRules.WS_CHARS) }

    /** Narrow a pattern back to stock-Java semantics — the negative control. */
    private fun narrowedWhitespace(pattern: String) =
        pattern.replace(TxtTocRules.WS, "\\s").replace(TxtTocRules.WS_CHARS, "\\s")

    private fun narrowedDigits(pattern: String) = pattern.replace(TxtTocRules.DIGIT_CHARS, "\\d")

    // ---------------------------------------------------------------- structure / fidelity

    @Test
    fun defaults_containsAll25Rules_inSerialNumberOrder() {
        assertEquals("all 25 iOS rules are ported", 25, rules.size)
        assertEquals((1..25).toList(), rules.map { it.id })
        assertEquals(
            "serialNumber == id on iOS, and list order IS tie-break order",
            (1..25).toList(), rules.map { it.serialNumber },
        )
        rules.forEach {
            assertTrue("rule ${it.id} has a name", it.name.isNotBlank())
            assertTrue("rule ${it.id} has an example", it.example.isNotBlank())
            assertTrue("rule ${it.id} has a pattern", it.pattern.isNotBlank())
        }
    }

    @Test
    fun defaults_enabledIdsAreExactly_1_2_3_4_5_6_7_8_9_10_13_14_20_23() {
        // Pins the iOS DATA (TXTTocRuleEngine.swift:142-350, broadened by bug #83), NOT the
        // stale iOS header comment at :27 which still claims "8 enabled".
        assertEquals(
            listOf(1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 13, 14, 20, 23),
            rules.filter { it.enabled }.map { it.id },
        )
        assertEquals(
            listOf(11, 12, 15, 16, 17, 18, 19, 21, 22, 24, 25),
            rules.filterNot { it.enabled }.map { it.id },
        )
    }

    @Test
    fun ids_andPatterns_areUnique() {
        assertEquals(25, rules.map { it.id }.toSet().size)
        assertEquals("no duplicated pattern survived the port", 25, rules.map { it.pattern }.toSet().size)
    }

    @Test
    fun everyRule_compiles_underMultiline() {
        rules.forEach { assertNotNull("rule ${it.id} compiles", compiled(it)) }
    }

    @Test
    fun everyRule_matchesItsOwnExample() {
        rules.forEach {
            assertTrue(
                "rule ${it.id} (${it.name}) must match its own example '${it.example}'",
                compiled(it).containsMatchIn(it.example),
            )
        }
    }

    // ---------------------------------------------------------------- D1 — full-width digits

    @Test
    fun fullWidthDigits_matchOnJavaRegex() {
        val samples = mapOf(
            1 to "第１２章 全角数字",
            2 to "第１２３章 标题",
            3 to "Chapter １ Title",
            4 to "１、这个标题",
            7 to "卷５ 开源盛世",
            9 to "Volume １ Title",
            10 to "Book １ Title",
            11 to "Act １ Title",
            12 to "Scene １ Title",
            13 to "(１) 标题",
            14 to "１.标题",
            22 to "第１章 始まり",
            23 to "第１回 标题",
        )
        val population = digitRules()
        assertEquals(
            "the D1 sample table must cover EVERY rule using the digit class (incl. disabled 11/12/22)",
            population.map { it.id }.toSet(), samples.keys,
        )
        assertEquals("13 of the 25 rules use \\d on iOS", 13, population.size)

        population.forEach { rule ->
            val sample = samples.getValue(rule.id)
            assertTrue(
                "rule ${rule.id} must match full-width digits on java.util.regex: '$sample'",
                compiled(rule).containsMatchIn(sample),
            )
            assertFalse(
                "negative control: bare \\d must NOT match '$sample' (rule ${rule.id})",
                Regex(narrowedDigits(rule.pattern), RegexOption.MULTILINE).containsMatchIn(sample),
            )
        }
    }

    // ---------------------------------------------------------------- D1b — widened whitespace

    /** U+3000 IDEOGRAPHIC SPACE separators; the NBSP variants are derived by substitution. */
    private val ideographicSamples = mapOf(
        1 to "第${IDEO}一${IDEO}章 标题",
        2 to "第${IDEO}一${IDEO}章 标题",
        3 to "Chapter${IDEO}1 Title",
        6 to "正文${IDEO}第一章",
        7 to "卷${IDEO}五 开源盛世",
        9 to "Volume${IDEO}1 Title",
        10 to "Book${IDEO}1 Title",
        11 to "Act${IDEO}1 Title",
        12 to "Scene${IDEO}1 Title",
        15 to "III${IDEO}标题",
        16 to "甲${IDEO}标题",
        17 to "０１${IDEO}标题",
        21 to "〔一〕$IDEO",
        23 to "第${IDEO}一${IDEO}回 标题",
    )

    @Test
    fun ideographicSpaceSeparator_matchesOnJavaRegex() {
        assertWhitespaceSamples(ideographicSamples, "U+3000")
    }

    @Test
    fun nbspSeparator_matchesOnJavaRegex() {
        assertWhitespaceSamples(
            ideographicSamples.mapValues { (_, sample) -> sample.replace(IDEO, NBSP) },
            "U+00A0",
        )
    }

    private fun assertWhitespaceSamples(samples: Map<Int, String>, label: String) {
        val population = whitespaceRules()
        assertEquals(
            "the D1b sample table must cover EVERY rule with a \\s position (incl. disabled 11/12/15/16/17/21)",
            population.map { it.id }.toSet(), samples.keys,
        )
        assertEquals("14 of the 25 rules use \\s on iOS", 14, population.size)

        population.forEach { rule ->
            val sample = samples.getValue(rule.id)
            assertTrue(
                "rule ${rule.id} must accept a $label separator: '$sample'",
                compiled(rule).containsMatchIn(sample),
            )
            assertFalse(
                "negative control: bare \\s must NOT match the $label sample (rule ${rule.id})",
                Regex(narrowedWhitespace(rule.pattern), RegexOption.MULTILINE).containsMatchIn(sample),
            )
        }
    }

    // ---------------------------------------------------------------- banned constructs

    @Test
    fun noRule_setsDotMatchesAll() {
        // The bounded `.{0,30}$` tail is what confines a title to ONE line; DOTALL would let a
        // "title" swallow the chapter. No rule may enable it via an inline flag.
        rules.forEach {
            assertFalse("rule ${it.id} must not enable DOTALL inline", inlineFlags(it.pattern).contains('s'))
        }
    }

    @Test
    fun noRule_setsIgnoreCase() {
        // The rules spell both cases explicitly ([Cc]hapter), which avoids non-ASCII case-folding
        // divergence between ICU and Java entirely. IGNORE_CASE would reintroduce it.
        rules.forEach {
            assertFalse("rule ${it.id} must not enable IGNORE_CASE inline", inlineFlags(it.pattern).contains('i'))
        }
        listOf(3 to "[Cc]hapter", 9 to "[Vv]ol", 10 to "[Bb]ook", 20 to "[Pp]rologue").forEach { (id, spelling) ->
            assertTrue(
                "rule $id spells both cases explicitly instead of relying on a flag",
                rules.first { it.id == id }.pattern.contains(spelling),
            )
        }
    }

    @Test
    fun noRule_usesUnicodeCharacterClassFlag() {
        // (?U) would fix \d and \s in one stroke but ALSO redefines \w, \b, POSIX classes and
        // case folding. The surgical explicit classes are the fix (plan §3.5 "Why not (?U)").
        rules.forEach {
            assertTrue(
                "rule ${it.id} must not carry ANY inline flag group (found '${inlineFlags(it.pattern)}')",
                inlineFlags(it.pattern).isEmpty(),
            )
        }
    }

    /** The flag letters of every inline flag group `(?idmsuxU…)` in a pattern; empty when none. */
    private fun inlineFlags(pattern: String): String =
        Regex("""\(\?(?![:=!<>])([a-zA-Z-]*)[:)]""").findAll(pattern)
            .joinToString("") { it.groupValues[1] }

    @Test
    fun noRule_containsBareBackslashD_orBackslashS() {
        rules.forEach {
            val outsideWidenedClasses = it.pattern
                .replace(TxtTocRules.WS, "")
                .replace(TxtTocRules.WS_CHARS, "")
                .replace(TxtTocRules.DIGIT_CHARS, "")
            assertFalse("rule ${it.id} still has a bare \\d — D1 unfixed", outsideWidenedClasses.contains("\\d"))
            assertFalse("rule ${it.id} still has a bare \\s — D1b unfixed", outsideWidenedClasses.contains("\\s"))
        }
    }

    // ---------------------------------------------------------------- edge cases

    @Test
    fun emptyText_matchesNoRule() {
        rules.forEach { assertFalse("rule ${it.id} must not match empty text", compiled(it).containsMatchIn("")) }
    }

    @Test
    fun everyRulesExample_anchorsUnderLf_crlf_andCr() {
        listOf("\n", "\r\n", "\r").forEach { eol ->
            rules.forEach { rule ->
                val text = "prose$eol${rule.example}${eol}prose"
                val match = compiled(rule).find(text)
                assertNotNull("rule ${rule.id} must still match with ${eolName(eol)} endings", match)
                assertEquals(
                    "rule ${rule.id}: the ${eolName(eol)} match must be the heading LINE, not a run-on",
                    rule.example.trim(), match!!.value.trim(),
                )
            }
        }
    }

    private fun eolName(eol: String) = when (eol) {
        "\n" -> "LF"
        "\r\n" -> "CRLF"
        else -> "CR"
    }

    @Test
    fun leadingWs_widenedPerPlan_consumesAPrecedingBlankLineTerminator() {
        // DOCUMENTED CONSEQUENCE of plan §3.5's "the leading [space, U+3000, tab]{0,4} indent
        // class is normalized to WS{0,4}": WS is a superset that includes line terminators, so at
        // a BLANK line the indent can consume that line's own terminator and the match starts one
        // line early. Titles are unaffected (they are trimmed), but the reported source offset is
        // the blank line's start. Pinned here so WI-2's offset tests inherit a known value rather
        // than a surprise.
        val rule1 = rules.first { it.id == 1 }
        val match = compiled(rule1).find("\n第一章 标题")
        assertNotNull(match)
        assertEquals("match starts at the blank line, not the heading line", 0, match!!.range.first)
        assertEquals("the title is unaffected once trimmed", "第一章 标题", match.value.trim())
    }

    @Test
    fun pathologicalNumeralRun_terminatesQuickly() {
        // R4 (ReDoS): 2 000 consecutive CJK numerals with no unit character. The bounded
        // `.{0,30}$` tail keeps the search space small — measured at ~1 ms (plan Appendix A.3).
        val pathological = "第" + "一".repeat(2000) + "的故事没有章字"
        val started = System.nanoTime()
        val found = compiled(rules.first { it.id == 1 }).containsMatchIn(pathological)
        val elapsedMs = (System.nanoTime() - started) / 1_000_000
        assertFalse("no unit character, so no match", found)
        assertTrue("rule 1 must not backtrack catastrophically (took ${elapsedMs}ms)", elapsedMs < 5_000)
    }
}
