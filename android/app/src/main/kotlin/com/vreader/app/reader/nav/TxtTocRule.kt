// Purpose: Model for one TXT table-of-contents detection rule (feature #139 WI-1).
// The Kotlin analog of iOS `TXTTocRule` (vreader/Services/TXT/TXTTocRule.swift) — the
// 25 regex rules originally ported from Legado's txtTocRule.json. The rule DATA lives in
// [TxtTocRules]; this file is only its shape.
//
// Key decisions:
// - `id`/`serialNumber`/`enabled` mirror iOS 1:1 so both platforms detect the same chapters.
// - `pattern` is a raw regex STRING, not a compiled `Regex`: compilation flags are the
//   engine's contract (MULTILINE only — never DOT_MATCHES_ALL / IGNORE_CASE), and a data
//   class of Strings stays cheap to hold, compare, and (later) persist.
// - Field named `pattern` rather than iOS's `rule` — `TxtTocRule.rule` reads as a self
//   reference in Kotlin call sites.
//
// @coordinates-with: TxtTocRules.kt, TxtTocRuleEngine.kt
package com.vreader.app.reader.nav

/**
 * A single TXT chapter-detection rule.
 *
 * @param id           unique identifier (matches iOS / Legado numbering).
 * @param enabled      whether the rule participates in auto-detection.
 * @param name         human-readable description of what the rule matches.
 * @param pattern      regex pattern string — applied with `RegexOption.MULTILINE` ONLY.
 * @param example      a sample line the pattern matches (pinned by test).
 * @param serialNumber original Legado ordering key; detection ties break toward the
 *                     lowest serial number, so list order is load-bearing.
 */
data class TxtTocRule(
    val id: Int,
    val enabled: Boolean,
    val name: String,
    val pattern: String,
    val example: String,
    val serialNumber: Int,
)
