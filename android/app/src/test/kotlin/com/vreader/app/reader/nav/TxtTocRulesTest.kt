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

        /** iOS's literal leading-indent class, `^[ U+3000 \t]{0,4}` (TXTTocRuleEngine.swift). */
        val IOS_INDENT: String = "^[ " + IDEO + "\\t]{0,4}"

        /**
         * The rules that use `\d` / `\s` **in iOS**, read off the Swift source — NOT derived from
         * the Kotlin under test. Deriving both sides from the implementation would let one wrong
         * removal plus one wrong addition cancel out; these are the independent expectation.
         */
        val IOS_DIGIT_RULE_IDS = setOf(1, 2, 3, 4, 7, 9, 10, 11, 12, 13, 14, 22, 23)
        val IOS_WHITESPACE_RULE_IDS = setOf(1, 2, 3, 6, 7, 9, 10, 11, 12, 15, 16, 17, 21, 23)
    }

    private val rules: List<TxtTocRule> get() = TxtTocRules.defaults

    private fun compiled(rule: TxtTocRule) = Regex(rule.pattern, RegexOption.MULTILINE)

    /** The pattern with the leading indent class stripped — i.e. its non-indent body. */
    private fun body(rule: TxtTocRule) = rule.pattern.removePrefix(TxtTocRules.INDENT)

    /** Rules that reference the widened digit class (the D1 population), derived from the data. */
    private fun digitRules() = rules.filter { it.pattern.contains(TxtTocRules.DIGIT_CHARS) }

    /** Rules with a whitespace position beyond the leading indent (the D1b population). */
    private fun whitespaceRules() = rules.filter { body(it).contains(TxtTocRules.WS_CHARS) }

    /**
     * Undo the two permitted substitutions, turning a shipped pattern back into the iOS text it
     * was ported from. Bracketed forms are undone first so both an in-class occurrence
     * (`[0-9…〇零…]` → `[\d〇零…]`) and a standalone one (`[0-9…]{1,4}` → `\d{1,4}`) round-trip.
     */
    private fun roundTripToIos(pattern: String) = pattern
        .replace(TxtTocRules.WS, "\\s")
        .replace(TxtTocRules.WS_CHARS, "\\s")
        .replace(TxtTocRules.DIGIT, "\\d")
        .replace(TxtTocRules.DIGIT_CHARS, "\\d")

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

    /**
     * The iOS table, transcribed INDEPENDENTLY from `TXTTocRuleEngine.swift:142-350` — id to
     * (name, pattern body after the leading indent, example). This is the golden source: the
     * shipped rule must round-trip back to exactly this text once the two permitted
     * substitutions are undone. Transcribing rather than deriving is the point — a pattern and
     * its example can otherwise drift together and still satisfy "matches its own example".
     */
    private val iosRules: Map<Int, Triple<String, String, String>> = mapOf(
        1 to Triple(
            "中文章节（通用）",
            "(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\\s{0,4}" +
                "[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\\s{0,4}" +
                "(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|篇(?!张))).{0,30}$",
            "第一章 标题",
        ),
        2 to Triple(
            "中文数字章节",
            "[第（\\(]?\\s{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?" +
                "\\s{0,4}[章节卷集部篇回话]\\s?.{0,30}$",
            "第123章 标题",
        ),
        3 to Triple(
            "英文Chapter/Section/Part",
            "(?:[Cc]hapter|[Ss]ection|[Pp]art|[Ee]pisode)\\s{0,4}\\d{1,4}.{0,30}$",
            "Chapter 1 Title",
        ),
        4 to Triple("数字+标点标题", "\\d{1,5}[：:,.， 、_—\\-].{1,30}$", "1、这个标题"),
        5 to Triple("特殊符号·章节", "[【\\[☆★●◆◇○◎□■△▲※卐].{1,30}$", "【第一章 标题】"),
        6 to Triple("正文+标题", "正文\\s.{0,20}$", "正文 第一章"),
        7 to Triple(
            "中文卷/篇/部/集",
            "(?:卷|篇|部|集)\\s{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+.{0,30}$",
            "卷五 开源盛世",
        ),
        8 to Triple("星号标题", "[☆★].{1,30}$", "☆、第一个故事"),
        9 to Triple("Volume + Number", "[Vv]ol(?:ume)?\\s{0,4}\\d{1,4}.{0,30}$", "Volume 1 Title"),
        10 to Triple("Book + Number", "[Bb]ook\\s{0,4}\\d{1,4}.{0,30}$", "Book 1 Title"),
        11 to Triple("Act + Number", "[Aa]ct\\s{0,4}\\d{1,4}.{0,30}$", "Act 1 Title"),
        12 to Triple("Scene + Number", "[Ss]cene\\s{0,4}\\d{1,4}.{0,30}$", "Scene 1 Title"),
        13 to Triple("数字序号（圆括号）", "[\\(（]\\d{1,5}[\\)）].{1,30}$", "(1) 标题"),
        14 to Triple("数字序号（点号）", "\\d{1,5}\\..{1,30}$", "1.标题"),
        15 to Triple(
            "罗马数字章节",
            "(?:I{1,3}|IV|VI{0,3}|IX|XI{0,3}|XIV|XVI{0,3}|XIX|XXI{0,3})[.、：:\\s].{0,30}$",
            "III. 标题",
        ),
        16 to Triple("天干地支", "[甲乙丙丁戊己庚辛壬癸][.、：:\\s].{0,30}$", "甲、标题"),
        17 to Triple("全角数字章节", "[０-９]{1,5}[.、：:\\s].{0,30}$", "０１、标题"),
        18 to Triple("圆圈数字", "[①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳].{0,30}$", "① 标题"),
        19 to Triple(
            "括号+中文数字",
            "[（\\(][零一二三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+[）\\)].{0,30}$",
            "(一) 标题",
        ),
        20 to Triple(
            "Prologue/Epilogue/Interlude",
            "(?:[Pp]rologue|[Ee]pilogue|[Ii]nterlude|[Pp]reface|[Ff]oreword|[Aa]fterword|" +
                "[Ii]ntroduction|[Cc]onclusion).{0,30}$",
            "Prologue",
        ),
        21 to Triple("中文括号标题", "〔.{1,20}〕\\s{0,4}$", "〔一〕"),
        22 to Triple(
            "日文章节",
            "第[\\d〇零一二三四五六七八九十百千万]+?(?:章|節|巻|話|編).{0,30}$",
            "第一章 始まり",
        ),
        23 to Triple(
            "中文回/话",
            "第\\s{0,4}[\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟]+?\\s{0,4}[回话].{0,30}$",
            "第一回 标题",
        ),
        24 to Triple("短线分隔章节", "[—\\-]{3,}.{0,30}$", "--- 章节标题"),
        25 to Triple("等号分隔章节", "[=]{3,}.{0,30}$", "=== 章节标题"),
    )

    @Test
    fun everyRule_roundTripsToTheIosPatternExactly() {
        assertEquals("the golden table covers all 25 iOS rules", 25, iosRules.size)
        rules.forEach { rule ->
            val (name, iosBody, example) = iosRules.getValue(rule.id)
            assertEquals("rule ${rule.id} name", name, rule.name)
            assertEquals("rule ${rule.id} example", example, rule.example)
            assertEquals(
                "rule ${rule.id} must differ from iOS ONLY by the D1/D1b substitutions",
                IOS_INDENT + iosBody, roundTripToIos(rule.pattern),
            )
        }
    }

    @Test
    fun everyRule_keepsTheLiteralIosIndentClass() {
        // The indent is the one whitespace position iOS did NOT write as \s, so widening it
        // would be a NEW divergence, not a repair — and one that shifts heading offsets onto the
        // preceding blank line. Pinned so the plan's §3.5 wording cannot reintroduce it.
        assertEquals("INDENT is iOS's literal class", IOS_INDENT, TxtTocRules.INDENT)
        rules.forEach {
            assertTrue(
                "rule ${it.id} must start with the literal indent class, not a widened one",
                it.pattern.startsWith(IOS_INDENT),
            )
            assertFalse(
                "rule ${it.id} must not widen the indent to WS",
                it.pattern.startsWith("^${TxtTocRules.WS}"),
            )
        }
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
            "the shipped rules must widen \\d in EXACTLY the rules iOS wrote it in",
            IOS_DIGIT_RULE_IDS, population.map { it.id }.toSet(),
        )
        assertEquals(
            "the D1 sample table must cover EVERY such rule (incl. disabled 11/12/22)",
            IOS_DIGIT_RULE_IDS, samples.keys,
        )

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
            "the shipped rules must widen \\s in EXACTLY the rules iOS wrote it in",
            IOS_WHITESPACE_RULE_IDS, population.map { it.id }.toSet(),
        )
        assertEquals(
            "the D1b sample table must cover EVERY such rule (incl. disabled 11/12/15/16/17/21)",
            IOS_WHITESPACE_RULE_IDS, samples.keys,
        )

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

    /**
     * The flag letters of every inline flag group in a pattern; empty when none.
     *
     * A deliberately simple textual scan of the conventional Java forms — `(?i)`, `(?i:…)`,
     * `(?i-m)`, `(?idmsux)` — not a regex parser. That is sufficient here because these patterns
     * are a fixed, reviewed data table, and [noRule_containsAnyForbiddenFlagToken] backstops it
     * with a blunt token check that cannot be out-parsed.
     */
    private fun inlineFlags(pattern: String): String =
        Regex("""\(\?(?![:=!<>])([a-zA-Z-]*)[:)]""").findAll(pattern)
            .joinToString("") { it.groupValues[1] }

    @Test
    fun noRule_containsAnyForbiddenFlagToken() {
        // Backstop for inlineFlags(): whatever the exact syntax, a flag group must begin with
        // "(?" followed by a flag letter. No rule may contain that sequence at all.
        val forbidden = listOf("(?i", "(?s", "(?m", "(?u", "(?U", "(?x", "(?d", "(?-")
        rules.forEach { rule ->
            forbidden.forEach { token ->
                assertFalse(
                    "rule ${rule.id} must not contain the inline-flag token '$token'",
                    rule.pattern.contains(token),
                )
            }
        }
    }

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
    fun headingAfterBlankLines_matchesAtTheHeadingLine_notTheBlankLine() {
        // The regression behind the reverted indent widening (Gate-4 HIGH). Blank lines before a
        // chapter heading are ubiquitous in real books; a widened indent would consume the blank
        // line's own terminator and start the match there, so every such heading's source offset
        // — WI-2's navigation locator — would land one line early.
        val rule1 = rules.first { it.id == 1 }
        listOf("\n", "\n\n", "\r\n\r\n").forEach { blanks ->
            val match = compiled(rule1).find(blanks + "第一章 标题")
            assertNotNull("rule 1 still matches after blank lines", match)
            assertEquals(
                "the match must start AT the heading, not at the preceding blank line",
                blanks.length, match!!.range.first,
            )
            assertEquals("第一章 标题", match.value)
        }
        // …and a genuine in-line indent is still consumed, exactly as iOS does it.
        // Braced: a CJK letter is a valid Kotlin identifier character, so `$IDEO第一章` would
        // parse as the identifier `IDEO第一章`.
        val indented = compiled(rule1).find("\n$IDEO${IDEO}第一章 标题")
        assertNotNull(indented)
        assertEquals("the U+3000 indent is part of the match, as on iOS", 1, indented!!.range.first)
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
