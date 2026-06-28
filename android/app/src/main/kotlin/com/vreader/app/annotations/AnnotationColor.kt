// Purpose: feature #123 (Android EPUB highlights & notes) — the highlight color palette.
// The 5 colors are DESIGN parity (vreader-android-annotations.jsx HL_COLORS), NOT iOS-model parity:
// iOS NamedHighlightColor has 4 (yellow/pink/green/blue, no red). Storage is the `key` string, so an
// Android-only `red` highlight round-trips through the #113 backup as an unknown color on iOS rather
// than corrupting data — `from()` is nil-tolerant for the same forward-compat reason.
package com.vreader.app.annotations

/** A highlight color. `key` is the stored, forward-compatible identifier; the hex triplet drives the
 *  dot / text-wash / left-rule rendering (design `HL_COLORS`). */
enum class AnnotationColor(val key: String, val dotHex: String, val washHex: String, val ruleHex: String) {
    yellow("yellow", "#e6b800", "#47e6b800", "#d9a800"),
    green("green", "#5a9a6e", "#425a9a6e", "#5a9a6e"),
    blue("blue", "#5c8fc4", "#425c8fc4", "#5c8fc4"),
    pink("pink", "#cf7a9a", "#42cf7a9a", "#cf7a9a"),
    red("red", "#b5503f", "#3db5503f", "#b5503f"),
    ;

    companion object {
        /** Parse a stored color string → the matching color, or null for an unknown value (graceful,
         *  the iOS `NamedHighlightColor.from` analog). Callers default to [yellow] on null. */
        fun from(storage: String?): AnnotationColor? = entries.firstOrNull { it.key == storage }

        /** The palette order shown in the selection popover's color row. */
        val palette: List<AnnotationColor> = entries.toList()

        val DEFAULT: AnnotationColor = yellow
    }
}
