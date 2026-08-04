// Purpose: The 25 TXT chapter-detection rules, ported 1:1 from iOS
// `TXTTocRuleEngine.buildDefaultRules()` (vreader/Services/TXT/TXTTocRuleEngine.swift:142-350),
// itself a port of Legado's txtTocRule.json. Data only — detection/extraction is the engine's.
// Feature #139 WI-1.
//
// Key decisions:
// - Ids, serialNumbers and `enabled` flags mirror iOS EXACTLY (14 enabled: 1-10, 13, 14, 20, 23),
//   so a book that gets a Contents on iOS gets the same one on Android. The port follows iOS's
//   DATA, not its stale header comment (TXTTocRuleEngine.swift:27 still says "8 enabled").
// - List order IS serialNumber order, and detection breaks ties toward the FIRST rule, so the
//   order is behaviour, not presentation.
// - TWO regex-engine divergences are repaired here, because iOS runs ICU (NSRegularExpression)
//   and Android runs java.util.regex (see [DIGIT] and [WS]). Everything else is verbatim.
// - Patterns are compiled by the caller with MULTILINE and NOTHING else: DOT_MATCHES_ALL would
//   let a title swallow the chapter (the bounded `.{0,30}$` tail is what confines it to one
//   line), and IGNORE_CASE would reintroduce the Unicode case-folding divergence the explicit
//   `[Cc]hapter`-style spellings avoid. No pattern carries an inline flag either — `(?U)` in
//   particular is banned: it would fix \d and \s but ALSO redefine \w, \b and POSIX classes.
//
// - The leading indent class stays iOS's LITERAL `[space, U+3000, tab]` (see [INDENT]). The
//   plan's §3.5 asked for it to be normalized to [WS] too; that was implemented, audited, and
//   reverted, because [WS] contains LINE TERMINATORS while iOS's indent class does not. At a
//   blank line the widened indent consumed that line's own terminator, so a match started one
//   line early and WI-2 would have turned a systematically-off-by-one-line offset into a
//   navigation locator. iOS never wrote `\s` in the indent, so there is no ICU divergence to
//   repair here — and the plan's own Appendix A.5 non-regression measurement kept this class
//   literal, so it never covered the normalization it asked for.
//
// @coordinates-with: TxtTocRule.kt, TxtTocRuleEngine.kt
package com.vreader.app.reader.nav

/**
 * The default TXT TOC rule set (all 25; 14 enabled), plus the two character classes that repair
 * the ICU-vs-Java regex divergences.
 */
object TxtTocRules {

    // ------------------------------------------------------------------ divergence repairs

    /**
     * D1b — the ICU `\s` equivalent for `java.util.regex`, as CLASS CONTENTS (no brackets) so it
     * can also be spliced into a larger character class such as `[.、：:$WS_CHARS]`.
     *
     * ICU defines `\s` as `[\t\n\v\f\r\p{Z}]`; Java's is ASCII-only (`[ \t\n\x0B\f\r]`).
     * `\p{Z}` = Zs ∪ Zl ∪ Zp, so this covers U+3000 IDEOGRAPHIC SPACE, NBSP, U+2028 and U+2029;
     * `\x{0085}` (NEL) is added explicitly because it is `Cc`, not `Z`.
     *
     * Load-bearing for CJK: U+3000 is the normal separator in Chinese typesetting, so a book
     * whose headings read `第 一 章` builds a TOC on iOS and, with bare Java `\s`, none here.
     */
    const val WS_CHARS = "\\s\\p{Z}\\x{0085}"

    /** [WS_CHARS] as a standalone character class — one whitespace character, ICU semantics. */
    const val WS = "[$WS_CHARS]"

    /**
     * D1 — the ICU `\d` equivalent, as CLASS CONTENTS. ICU `\d` is Unicode `Nd` (it matches
     * `０-９`); Java's `\d` is ASCII `[0-9]`, so a verbatim port silently fails on full-width
     * digits — i.e. on exactly the CJK books this feature exists for.
     */
    const val DIGIT_CHARS = "0-9０-９"

    /** [DIGIT_CHARS] as a standalone character class — one digit, ICU semantics. */
    const val DIGIT = "[$DIGIT_CHARS]"

    // ------------------------------------------------------------------ numeral inventories
    // Three DISTINCT sets on iOS; the differences are deliberate and preserved verbatim.

    /** Rules 1, 2, 7, 23 — Chinese numerals incl. 两 and the financial forms 壹…仟. */
    private const val CJK_NUM = "〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟"

    /** Rule 22 (Japanese) — no 两, no financial forms. */
    private const val CJK_NUM_JA = "〇零一二三四五六七八九十百千万"

    /** Rule 19 (parenthesised) — no 〇, no 两. */
    private const val CJK_NUM_PAREN = "零一二三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟"

    /**
     * The bounded leading-indent prefix every rule shares — iOS's LITERAL `[space, U+3000, tab]`
     * class, deliberately NOT widened to [WS].
     *
     * iOS wrote this class out by hand rather than as `\s`, so there is no ICU-vs-Java
     * divergence to repair. Widening it would be a *new* divergence with a real cost: [WS]
     * matches line terminators, so at a blank line the indent swallows that line's own
     * terminator and the match — hence the heading's source offset, hence WI-2's navigation
     * locator — starts one line early.
     *
     * U+3000 is built from its code point rather than written literally: an invisible character
     * in a regex is exactly what Gate-2 rounds 3 and 4 caught being silently normalized.
     */
    internal val INDENT = "^[ " + Char(0x3000) + "\\t]{0,4}"

    // ------------------------------------------------------------------ the rules

    /** All 25 rules in serialNumber order. 14 ship enabled — same set as iOS. */
    val defaults: List<TxtTocRule> = listOf(
        TxtTocRule(
            id = 1,
            enabled = true,
            name = "中文章节（通用）",
            pattern = "$INDENT(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|" +
                "第$WS{0,4}[$DIGIT_CHARS$CJK_NUM]+?$WS{0,4}" +
                "(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|篇(?!张))).{0,30}$",
            example = "第一章 标题",
            serialNumber = 1,
        ),
        TxtTocRule(
            id = 2,
            enabled = true,
            name = "中文数字章节",
            pattern = "$INDENT[第（\\(]?$WS{0,4}[$DIGIT_CHARS$CJK_NUM]+?$WS{0,4}[章节卷集部篇回话]$WS?.{0,30}$",
            example = "第123章 标题",
            serialNumber = 2,
        ),
        TxtTocRule(
            id = 3,
            enabled = true,
            name = "英文Chapter/Section/Part",
            pattern = "$INDENT(?:[Cc]hapter|[Ss]ection|[Pp]art|[Ee]pisode)$WS{0,4}$DIGIT{1,4}.{0,30}$",
            example = "Chapter 1 Title",
            serialNumber = 3,
        ),
        TxtTocRule(
            id = 4,
            enabled = true,
            name = "数字+标点标题",
            pattern = "$INDENT$DIGIT{1,5}[：:,.， 、_—\\-].{1,30}$",
            example = "1、这个标题",
            serialNumber = 4,
        ),
        TxtTocRule(
            id = 5,
            enabled = true,
            name = "特殊符号·章节",
            pattern = "$INDENT[【\\[☆★●◆◇○◎□■△▲※卐].{1,30}$",
            example = "【第一章 标题】",
            serialNumber = 5,
        ),
        TxtTocRule(
            id = 6,
            enabled = true,
            name = "正文+标题",
            // `${'$'}INDENT` is braced because a CJK letter is a valid Kotlin identifier
            // character — an unbraced `$INDENT正文` would parse as the identifier `INDENT正文`.
            pattern = "${INDENT}正文$WS.{0,20}$",
            example = "正文 第一章",
            serialNumber = 6,
        ),
        TxtTocRule(
            id = 7,
            enabled = true,
            name = "中文卷/篇/部/集",
            pattern = "$INDENT(?:卷|篇|部|集)$WS{0,4}[$DIGIT_CHARS$CJK_NUM]+.{0,30}$",
            example = "卷五 开源盛世",
            serialNumber = 7,
        ),
        TxtTocRule(
            id = 8,
            enabled = true,
            name = "星号标题",
            pattern = "$INDENT[☆★].{1,30}$",
            example = "☆、第一个故事",
            serialNumber = 8,
        ),
        TxtTocRule(
            id = 9,
            enabled = true,
            name = "Volume + Number",
            pattern = "$INDENT[Vv]ol(?:ume)?$WS{0,4}$DIGIT{1,4}.{0,30}$",
            example = "Volume 1 Title",
            serialNumber = 9,
        ),
        TxtTocRule(
            id = 10,
            enabled = true,
            name = "Book + Number",
            pattern = "$INDENT[Bb]ook$WS{0,4}$DIGIT{1,4}.{0,30}$",
            example = "Book 1 Title",
            serialNumber = 10,
        ),
        TxtTocRule(
            id = 11,
            enabled = false,
            name = "Act + Number",
            pattern = "$INDENT[Aa]ct$WS{0,4}$DIGIT{1,4}.{0,30}$",
            example = "Act 1 Title",
            serialNumber = 11,
        ),
        TxtTocRule(
            id = 12,
            enabled = false,
            name = "Scene + Number",
            pattern = "$INDENT[Ss]cene$WS{0,4}$DIGIT{1,4}.{0,30}$",
            example = "Scene 1 Title",
            serialNumber = 12,
        ),
        TxtTocRule(
            id = 13,
            enabled = true,
            name = "数字序号（圆括号）",
            pattern = "$INDENT[\\(（]$DIGIT{1,5}[\\)）].{1,30}$",
            example = "(1) 标题",
            serialNumber = 13,
        ),
        TxtTocRule(
            id = 14,
            enabled = true,
            name = "数字序号（点号）",
            pattern = "$INDENT$DIGIT{1,5}\\..{1,30}$",
            example = "1.标题",
            serialNumber = 14,
        ),
        TxtTocRule(
            id = 15,
            enabled = false,
            name = "罗马数字章节",
            pattern = "$INDENT(?:I{1,3}|IV|VI{0,3}|IX|XI{0,3}|XIV|XVI{0,3}|XIX|XXI{0,3})[.、：:$WS_CHARS].{0,30}$",
            example = "III. 标题",
            serialNumber = 15,
        ),
        TxtTocRule(
            id = 16,
            enabled = false,
            name = "天干地支",
            pattern = "$INDENT[甲乙丙丁戊己庚辛壬癸][.、：:$WS_CHARS].{0,30}$",
            example = "甲、标题",
            serialNumber = 16,
        ),
        TxtTocRule(
            id = 17,
            enabled = false,
            name = "全角数字章节",
            // Deliberately NOT widened to [DIGIT]: on iOS this rule is full-width ONLY, and it is
            // the marker itself (not a `\d` shorthand), so D1 does not apply.
            pattern = "$INDENT[０-９]{1,5}[.、：:$WS_CHARS].{0,30}$",
            example = "０１、标题",
            serialNumber = 17,
        ),
        TxtTocRule(
            id = 18,
            enabled = false,
            name = "圆圈数字",
            pattern = "$INDENT[①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮⑯⑰⑱⑲⑳].{0,30}$",
            example = "① 标题",
            serialNumber = 18,
        ),
        TxtTocRule(
            id = 19,
            enabled = false,
            name = "括号+中文数字",
            pattern = "$INDENT[（\\(][$CJK_NUM_PAREN]+[）\\)].{0,30}$",
            example = "(一) 标题",
            serialNumber = 19,
        ),
        TxtTocRule(
            id = 20,
            enabled = true,
            name = "Prologue/Epilogue/Interlude",
            pattern = "$INDENT(?:[Pp]rologue|[Ee]pilogue|[Ii]nterlude|[Pp]reface|[Ff]oreword|" +
                "[Aa]fterword|[Ii]ntroduction|[Cc]onclusion).{0,30}$",
            example = "Prologue",
            serialNumber = 20,
        ),
        TxtTocRule(
            id = 21,
            enabled = false,
            name = "中文括号标题",
            pattern = "${INDENT}〔.{1,20}〕$WS{0,4}$",
            example = "〔一〕",
            serialNumber = 21,
        ),
        TxtTocRule(
            id = 22,
            enabled = false,
            name = "日文章节",
            pattern = "${INDENT}第[$DIGIT_CHARS$CJK_NUM_JA]+?(?:章|節|巻|話|編).{0,30}$",
            example = "第一章 始まり",
            serialNumber = 22,
        ),
        TxtTocRule(
            id = 23,
            enabled = true,
            name = "中文回/话",
            pattern = "${INDENT}第$WS{0,4}[$DIGIT_CHARS$CJK_NUM]+?$WS{0,4}[回话].{0,30}$",
            example = "第一回 标题",
            serialNumber = 23,
        ),
        TxtTocRule(
            id = 24,
            enabled = false,
            name = "短线分隔章节",
            pattern = "$INDENT[—\\-]{3,}.{0,30}$",
            example = "--- 章节标题",
            serialNumber = 24,
        ),
        TxtTocRule(
            id = 25,
            enabled = false,
            name = "等号分隔章节",
            pattern = "$INDENT[=]{3,}.{0,30}$",
            example = "=== 章节标题",
            serialNumber = 25,
        ),
    )
}
