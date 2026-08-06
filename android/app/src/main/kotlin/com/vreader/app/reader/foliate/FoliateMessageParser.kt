// Purpose: parse the `{name, detail}` wire JSON the foliate-js bundle posts over the WebView bridge
// into a typed [FoliateMessage]. Pure + side-effect-free so it is fully JVM-unit-testable (no WebView).
// Uses kotlinx.serialization (the module convention, cf. ReadiumLocatorBridge) — NOT org.json, which
// is a throwing stub under JVM unit tests. Owns which FIELD carries what; delegates the nested
// `book-ready.toc` tree walk to FoliateTocParser (feature #140 WI-1). Feature #126 WI-2.
//
// SIZE LIMITS live in two places, deliberately. The per-FIELD caps below (MAX_SELECTION_CHARS /
// MAX_CFI_CHARS) bound what a message may CARRY; the per-message-name RAW ceiling in
// FoliateBridgePolicy bounds the payload before this file's `parseToJsonElement` builds a tree from
// it. Field caps cannot do the latter job — by the time they run, the whole document is already
// parsed. Feature #142 WI-1.
package com.vreader.app.reader.foliate

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject

object FoliateMessageParser {

    /**
     * feature #142 WI-1 — maximum UTF-16 length of a selection's `text`. Over this the WHOLE message
     * is dropped, never truncated: the quote is persisted to Room, copied into `Locator.textQuote`,
     * hashed into the dedupe key via `canonicalJson()`, AND written into `annotations.json` on every
     * backup, so a truncated quote silently corrupts all four. 8 000 is far above any plausible
     * finger-drag selection and bounds the storage/backup-bloat vector a very large drag opens.
     */
    internal const val MAX_SELECTION_CHARS = 8_000

    /**
     * feature #142 WI-1 — maximum UTF-16 length of a CFI (`selection.cfi`, `annotation-show.value`).
     * Over this the message is dropped rather than truncated: a truncated CFI is not "less precise",
     * it resolves to a DIFFERENT range, which would paint or delete the wrong highlight.
     */
    internal const val MAX_CFI_CHARS = 4_000

    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    /**
     * Parse one bridge message. Returns `null` for input that isn't a usable message — non-JSON,
     * not an object, or missing/empty `name` — so a malformed/hostile payload degrades to "ignored"
     * rather than throwing into the WebView callback. Unknown-but-valid names map to [FoliateMessage.Other].
     */
    fun parse(raw: String): FoliateMessage? {
        val root = runCatching { json.parseToJsonElement(raw).jsonObject }.getOrNull() ?: return null
        val name = root.str("name") ?: return null
        val detail = (root["detail"] as? JsonObject) ?: JsonObject(emptyMap())
        return when (name) {
            "bridge-ready" -> FoliateMessage.BridgeReady
            "book-ready" -> FoliateMessage.BookReady(
                title = detail.str("title"),
                sectionTotal = detail.int("sections") ?: detail.int("sectionTotal") ?: 0,
                // Reading the field is this parser's job; walking the tree is FoliateTocParser's.
                // A missing `toc` hands over `null`, which is a legal input yielding an empty list.
                toc = FoliateTocParser.parse(detail["toc"]),
            )
            "relocate" -> FoliateMessage.Relocate(
                cfi = detail.str("cfi"),
                fraction = detail.dbl("fraction"),
                sectionIndex = detail.int("sectionIndex") ?: 0,
                sectionTotal = detail.int("sectionTotal") ?: 1,
                // feature #140 WI-4. Carried VERBATIM — `str` rejects blank/non-string but never
                // trims, because `foliateTocIndexFor` compares this against the parsed TOC hrefs by
                // exact string equality, with no normalization on either side (a trimmed,
                // case-folded, re-encoded or Unicode-normalized href would match the wrong row, or
                // none at all).
                tocHref = detail.str("tocHref"),
            )
            "error" -> FoliateMessage.Error(
                message = detail.str("message") ?: "unknown",
                type = detail.str("type"),
            )
            "goto-ack" -> {
                // Without a request id the ack resolves nothing — reject the whole message so a
                // mint-less / hostile ack never reaches the dispatcher's pending map.
                val id = detail.str("id") ?: return null
                FoliateMessage.GoToAck(
                    id = id,
                    ok = detail.bool("ok") ?: false,
                    cfi = detail.str("cfi"),
                    fraction = detail.dbl("fraction"),
                )
            }
            // feature #142 WI-1 — the annotation adapter's three inbound events. Note the RAW-length
            // ceiling for these names runs at the bridge, BEFORE this parser (FoliateBridgePolicy).
            "selection" -> {
                if (detail.bool("collapsed") == true) {
                    FoliateMessage.SelectionCleared
                } else {
                    // Both fields are load-bearing: without text there is nothing to store, without a
                    // cfi nothing to anchor or re-paint. Either missing → drop the whole message, and
                    // an over-cap field is dropped WHOLESALE rather than truncated (see the consts).
                    val text = detail.str("text")?.takeIf { it.length <= MAX_SELECTION_CHARS } ?: return null
                    val cfi = detail.str("cfi")?.takeIf { it.length <= MAX_CFI_CHARS } ?: return null
                    FoliateMessage.Selection(
                        text = text,
                        cfi = cfi,
                        sectionIndex = detail.int("index") ?: 0,
                        rect = detail.rect("rect"),
                    )
                }
            }
            "annotation-show" -> {
                // No CFI → nothing to resolve to a stored highlight → the message is useless (the
                // same reasoning that rejects an id-less goto-ack).
                val value = detail.str("value")?.takeIf { it.length <= MAX_CFI_CHARS } ?: return null
                FoliateMessage.AnnotationShow(value = value, sectionIndex = detail.int("index") ?: 0)
            }
            // Carries no variable-length field and is never dropped: the host answers it by re-applying
            // its whole recorded decoration set, which does not depend on the index being right.
            "create-overlay" -> FoliateMessage.OverlayCreated(sectionIndex = detail.int("index") ?: 0)
            else -> FoliateMessage.Other(name)
        }
    }

    private fun JsonObject.prim(key: String): JsonPrimitive? = this[key] as? JsonPrimitive

    /** Non-blank string content, or null (treats JSON null / blank / non-string as absent). */
    private fun JsonObject.str(key: String): String? =
        prim(key)?.takeIf { it.isString }?.content?.takeIf { it.isNotBlank() }

    /** Integer from a JSON number, or null. A quoted numeric STRING ("3") is NOT accepted. */
    private fun JsonObject.int(key: String): Int? =
        prim(key)?.takeUnless { it.isString }?.intOrNull

    /** FINITE double from a JSON number, or null. Quoted strings ("0.5", "NaN", "Infinity") and
     *  non-finite values are rejected — a hostile book must not corrupt the fraction resume anchor. */
    private fun JsonObject.dbl(key: String): Double? =
        prim(key)?.takeUnless { it.isString }?.doubleOrNull?.takeIf { it.isFinite() }

    /** Strict JSON boolean (only the literals `true`/`false`), or null. A quoted "true" / numeric 1
     *  is NOT accepted — a hostile goto-ack must not force a truthy `ok`. */
    private fun JsonObject.bool(key: String): Boolean? =
        prim(key)?.takeUnless { it.isString }?.let { it.booleanOrNull }

    /**
     * feature #142 WI-1 — a complete [SelectionRect], or null. ALL FOUR members must be present and
     * finite: a partial rect is worse than none, because a consumer cannot tell a genuine 0 from a
     * missing member. Zero-area and negative values are kept (a range ending at a line break really
     * does measure zero; a selection scrolled above the viewport really is negative).
     */
    private fun JsonObject.rect(key: String): SelectionRect? {
        val obj = this[key] as? JsonObject ?: return null
        return SelectionRect(
            x = obj.dbl("x") ?: return null,
            y = obj.dbl("y") ?: return null,
            width = obj.dbl("width") ?: return null,
            height = obj.dbl("height") ?: return null,
        )
    }
}
