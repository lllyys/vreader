// Purpose: turn the `toc` element of a foliate-js `book-ready` payload into a bounded, typed
// [FoliateTocItem] tree. Pure + side-effect-free so it is fully JVM-unit-testable (no WebView), and
// throw-free so a malformed or hostile payload degrades to "no TOC / partial TOC" on the WebView
// message callback thread rather than propagating out of it.
//
// SCOPE (feature #140 plan §5.4). The bounds here protect the KOTLIN parse stage only. foliate's own
// recursive `assignIDs` / `flatten` / `serializeTOC` walks run inside `readerAPI.open()` in the
// SHA-pinned bundle BEFORE this code sees anything; a TOC pathological enough to break them posts
// `error` instead of `book-ready`, which Azw3Document already maps to a corrupt-book state. That
// exposure is pre-existing and unchanged — no bound here can make such a book open (follow-up F6).
// Feature #140 WI-1.
package com.vreader.app.reader.foliate

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

object FoliateTocParser {

    /**
     * Maximum number of nesting LEVELS parsed. Rows live at levels `0 .. MAX_TOC_DEPTH - 1`; the
     * subitems of a level-`(MAX_TOC_DEPTH - 1)` row are DROPPED and the parent row is KEPT.
     *
     * Dropping rather than rejecting because over-deep nesting is a display problem, not a
     * correctness one — the reachable chapters stay reachable. The sheet clamps indentation at 4
     * anyway, so nothing past that is visually distinguishable, and 12 is far above any real NCX.
     * The value also bounds this parser's recursion depth (see [parseLevel]).
     */
    internal const val MAX_TOC_DEPTH = 12

    /**
     * Maximum number of rows (nested rows included) a TOC may yield. Past this the WHOLE tree is
     * REJECTED, never truncated: a Contents list that silently stops at row N of a larger book is
     * worse than none, because the user cannot tell it is incomplete. 10 000 because an NCX is
     * authored rather than detected — no real Kindle book has that many rows — and the whole tree
     * is held in memory on the main thread.
     */
    internal const val MAX_TOC_ENTRIES = 10_000

    /**
     * Parse the `toc` element of a `book-ready` payload.
     *
     * Takes the ELEMENT, not the message envelope: reading `detail["toc"]` is
     * [FoliateMessageParser]'s job, so this stays a reusable TOC parser with no knowledge of which
     * message carried the tree.
     *
     * Every degenerate shape yields an empty or partial list and NEVER throws:
     * - `null` (the field is absent) — a legal input — and JSON `null` yield an empty list;
     * - a non-array `toc` yields an empty list;
     * - a non-object element is skipped, its siblings survive;
     * - a missing / null / non-array `subitems` means "no children";
     * - a missing / non-string `label` or `href` degrades to `""`.
     *
     * An empty result is therefore also what an over-cap TOC produces — the documented
     * "hide the Contents control" signal, not an error channel.
     */
    fun parse(tocElement: JsonElement?): List<FoliateTocItem> {
        val array = tocElement as? JsonArray ?: return emptyList()
        return parseLevel(array, depth = 0, budget = Budget()) ?: emptyList()
    }

    /** Remaining row allowance, shared across the whole walk so NESTED rows count too. */
    private class Budget {
        var remaining: Int = MAX_TOC_ENTRIES
    }

    /**
     * Depth-limited recursive descent: recursion is entered only while the CHILD level is still
     * below [MAX_TOC_DEPTH], so the stack depth is bounded by that constant regardless of how deeply
     * the payload nests. Returns `null` to mean "the entry cap was exceeded" — which propagates all
     * the way out, so the caller rejects the whole tree instead of truncating it.
     */
    private fun parseLevel(array: JsonArray, depth: Int, budget: Budget): List<FoliateTocItem>? {
        val out = ArrayList<FoliateTocItem>()
        for (element in array) {
            val obj = element as? JsonObject ?: continue
            if (budget.remaining == 0) return null
            budget.remaining--

            val subitemsArray = obj["subitems"] as? JsonArray
            val subitems = if (subitemsArray != null && depth + 1 < MAX_TOC_DEPTH) {
                parseLevel(subitemsArray, depth + 1, budget) ?: return null
            } else {
                emptyList()
            }

            out += FoliateTocItem(
                label = obj.stringOrEmpty("label"),
                href = obj.stringOrEmpty("href"),
                subitems = subitems,
            )
        }
        return out
    }

    /**
     * The VERBATIM string content of a JSON string field, or `""` when absent / null / not a string.
     * Deliberately no trimming and no blank filtering — labels and hrefs are preserved byte-for-byte
     * (the provider trims labels and drops blank rows; `relocate.tocHref` matching is byte-exact).
     */
    private fun JsonObject.stringOrEmpty(key: String): String =
        (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: ""
}
