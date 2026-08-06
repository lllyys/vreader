// Purpose: typed events the Android Foliate (AZW3/MOBI/KF8) reader receives from the foliate-js
// bundle running in a WebView. The bundle posts `{name, detail}` JSON over the bridge (the iOS
// `window.webkit.messageHandlers[name].postMessage` calls, forwarded by the Android shell shim to
// `addWebMessageListener`'s `vreaderHost`). FoliateMessageParser turns that wire JSON into these.
// Mirrors the iOS FoliateMessageParser contract. Feature #126 WI-2.
package com.vreader.app.reader.foliate

/** A parsed event from the foliate-js bundle. Only the messages this reader consumes are typed;
 *  everything else (tap/tts/search/section-load/external-link/…) maps to [Other] and is ignored.
 *  Feature #142 WI-1 promoted the three annotation events — `selection`, `annotation-show` and
 *  `create-overlay` — out of [Other] into the typed set. */
sealed interface FoliateMessage {

    /** The bundle loaded and `window.readerAPI` is available — safe to call `open`/`init`. */
    data object BridgeReady : FoliateMessage

    /**
     * The book parsed; metadata is available. `sectionTotal` is the spine length (> 0 when real).
     *
     * `toc` is the book's table of contents as foliate serialized it — a nested
     * `{label, href, subitems}` tree (feature #140 WI-1). Empty means "no usable TOC": the field was
     * absent, malformed, or over [FoliateTocParser.MAX_TOC_ENTRIES]. It defaults to empty so every
     * pre-#140 construction site still compiles and behaves identically.
     */
    data class BookReady(
        val title: String?,
        val sectionTotal: Int,
        val toc: List<FoliateTocItem> = emptyList(),
    ) : FoliateMessage

    /**
     * Reading position changed. `cfi` is foliate's platform-local CFI (lossy cross-platform);
     * `fraction` is the 0..1 progress (the canonical resume anchor).
     *
     * `tocHref` is the href of the TOC item foliate's own `TOCProgress` resolved for this position
     * (feature #140 WI-4), carried VERBATIM so `foliateTocIndexFor` can match it against the parsed
     * TOC by exact string equality — no trimming, case folding, re-encoding or Unicode normalization
     * on either side. `null` means "unknown chapter" — the field was absent, JSON `null`
     * (foliate posts `tocItem?.href ?? null`), blank, or not a string — never "no TOC". It defaults
     * to `null` so every pre-#140 construction site still compiles and behaves identically.
     */
    data class Relocate(
        val cfi: String?,
        val fraction: Double?,
        val sectionIndex: Int,
        val sectionTotal: Int,
        val tocHref: String? = null,
    ) : FoliateMessage

    /** A JS-side error (bundle init failure, open failure, unhandled rejection). */
    data class Error(val message: String, val type: String?) : FoliateMessage

    /**
     * feature #135 WI-2 — acknowledgement of an awaited [FoliateBridge.goTo]. The shell shim posts
     * this AFTER foliate's `view.goTo(...)` promise settles, echoing the request `id` the host minted
     * so the matching suspended [kotlinx.coroutines.CompletableDeferred] resolves. `ok` is the jump's
     * success; `cfi`/`fraction` carry the reached position when known. `id` is required (a mint-less
     * ack can resolve nothing → the parser rejects it).
     */
    data class GoToAck(
        val id: String,
        val ok: Boolean,
        val cfi: String?,
        val fraction: Double?,
    ) : FoliateMessage

    /**
     * feature #142 WI-1 — a finished text selection in the rendered book (the bundle's
     * `post("selection", {collapsed:false, text, cfi, index, rect})`, fired after a 300 ms
     * `selectionchange` debounce).
     *
     * [cfi] is foliate's CFI for the range; for MOBI/KF8 it is
     * `CFI.joinIndir(CFI.fake.fromIndex(index), CFI.fromRange(range))`, so its first step encodes the
     * spine index and it is the string handed straight back to `readerAPI.addAnnotation`.
     *
     * [text] and [cfi] are non-blank and within [FoliateMessageParser.MAX_SELECTION_CHARS] /
     * [FoliateMessageParser.MAX_CFI_CHARS] by construction — the parser drops the whole message
     * otherwise, never truncating (a truncated CFI resolves to the WRONG range; a truncated quote
     * corrupts the dedupe key and the backup row).
     *
     * [rect] is ADVISORY ONLY and is in the SECTION document's coordinate space, not the host's — the
     * bundle posts `range.getBoundingClientRect()` raw, without the `mapTapToHostViewport` correction
     * the tap path applies. The popover anchor is computed from the live layout instead, so nothing
     * may be built on this field; it is carried for diagnostics and as a last-ditch fallback.
     */
    data class Selection(
        val text: String,
        val cfi: String,
        val sectionIndex: Int,
        val rect: SelectionRect?,
    ) : FoliateMessage

    /** feature #142 WI-1 — the selection collapsed (the user tapped away). The bundle's
     *  `post("selection", {collapsed:true})`. */
    data object SelectionCleared : FoliateMessage

    /** feature #142 WI-1 — the user tapped an existing overlay (`post("annotation-show", …)`).
     *  [value] is the CFI the annotation was added under, which resolves back to a stored highlight. */
    data class AnnotationShow(val value: String, val sectionIndex: Int) : FoliateMessage

    /**
     * feature #142 WI-1 — a section mounted its overlayer (`post("create-overlay", …)`).
     *
     * Stored annotations for that section must be (re)applied here: `view.addAnnotation` silently
     * no-ops when the target section's overlayer does not exist yet, so a single apply at book-ready
     * paints only the sections mounted at that moment.
     */
    data class OverlayCreated(val sectionIndex: Int) : FoliateMessage

    /** A recognized-but-unconsumed event name (tap, tts-*, search-*, section-load, …). */
    data class Other(val name: String) : FoliateMessage
}

/**
 * feature #142 WI-1 — the bundle's serialized selection rectangle (`{x, y, width, height}`), in the
 * SECTION document's coordinate space. Deliberately NOT a [FoliateMessage]: it is a field of one.
 *
 * All four members are finite by construction (the parser rejects quoted, missing and non-finite
 * ones, yielding a null rect rather than a partial one). Zero-area and negative values ARE kept —
 * both are real layout outcomes, not corruption.
 */
data class SelectionRect(
    val x: Double,
    val y: Double,
    val width: Double,
    val height: Double,
)
