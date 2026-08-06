// Purpose: the PURE security decisions for the AZW3/foliate reader WebView, extracted from
// FoliateBridge so they are fully JVM-unit-testable (no WebView). Four boundaries, all keyed to the
// single trusted shell origin: which bridge messages to trust, how LARGE an inbound message may be
// for its name, which navigations to allow, and which resource requests to block (passive-exfil
// defense). Feature #126 WI-3; the raw ceiling is feature #142 WI-1.
package com.vreader.app.reader.foliate

import com.vreader.app.reader.foliate.FoliateAssetServer.SHELL_ORIGIN

object FoliateBridgePolicy {

    /**
     * A bridge message is trusted only if it comes from the MAIN frame of the trusted shell origin.
     * WI-0 proved `isMainFrame` alone is insufficient (a same-origin section script can call
     * `parent.vreaderHost` and be attributed to the main frame), so the LOAD-BEARING defense is the
     * bundle patch (book sections run no script). This is the second gate: even a main-frame call
     * from a foreign origin is rejected.
     */
    fun isTrustedMessage(sourceOrigin: String?, isMainFrame: Boolean): Boolean =
        isMainFrame && sourceOrigin == SHELL_ORIGIN

    // --- feature #142 WI-1: the PER-MESSAGE-NAME raw ceiling ------------------------------------
    //
    // WHY PER NAME AND NOT GLOBAL (this was designed, audited over three rounds, and the global
    // version WITHDRAWN — do not "simplify" it back):
    //
    // A global ceiling cannot exist. `book-ready` carries the book's whole TOC, and FoliateTocParser
    // preserves every label and href BYTE-FOR-BYTE by design, because `relocate.tocHref` matching is
    // exact string equality (feature #140). Label length is unbounded anywhere in this codebase or in
    // the contract, so a MAX_TOC_ENTRIES TOC with 200-char labels and hrefs is already ~4.37M chars
    // and a single 1 MB label is legal. Any global number is therefore a guess about what counts as
    // legitimate, and guessing low DROPS a valid `book-ready` and strands the reader before Loaded —
    // worse than the threat the cap addresses.
    //
    // So: a message may be capped only if THIS feature already bounds every variable-length field it
    // carries. That admits exactly the three names #142 introduces. `book-ready`, `relocate` and
    // everything else stay uncapped — unchanged from before this feature.
    //
    // WHAT THIS BUYS, HONESTLY. `WebMessageCompat.data` is already a materialised String when the
    // listener runs, so no host-side cap can prevent RECEIPT. What the ceiling prevents is the
    // JSON-tree amplification in `parseToJsonElement` (a JsonElement tree is several times its source
    // string) and everything downstream. The load-bearing defense remains the bundle patch (book
    // sections run no script, so they cannot post at all) plus the origin/main-frame gate above.

    /** Raw ceiling for `selection` — derived in plan §4.3: a 256-char skeleton + both field caps at
     *  worst-case `\uXXXX` escaping (8 000x6 + 4 000x6 = 72 000) ≈ 72 256, rounded up with headroom. */
    internal const val RAW_CEILING_SELECTION = 131_072

    /** Raw ceiling for `annotation-show` — 128-char skeleton + `value` at the CFI cap worst-case
     *  escaped (4 000x6 = 24 000) ≈ 24 128, rounded up with headroom. */
    internal const val RAW_CEILING_ANNOTATION_SHOW = 65_536

    /** Raw ceiling for `create-overlay` — a 56-char skeleton and no variable-length field at all. */
    internal const val RAW_CEILING_CREATE_OVERLAY = 1_024

    /** How far into a raw payload [rawCeilingFor] will look for the `"name"` key AND its value. */
    internal const val NAME_SNIFF_WINDOW = 256

    private val RAW_CEILINGS = mapOf(
        "selection" to RAW_CEILING_SELECTION,
        "annotation-show" to RAW_CEILING_ANNOTATION_SHOW,
        "create-overlay" to RAW_CEILING_CREATE_OVERLAY,
    )

    private const val NAME_KEY = "\"name\""

    /**
     * The raw-length ceiling for [raw]'s message name, or `null` meaning UNCAPPED.
     *
     * **This must never parse.** A cap-by-name that required the parse it exists to bound would be
     * circular. It reads at most [NAME_SNIFF_WINDOW] characters and requires `"name"` to be the FIRST
     * key of the top-level object — which is exactly what the shell shim emits
     * (`assets/foliate/reader.html` serialises `{name, detail}` with `name` first). A truncated or
     * otherwise unparseable payload is therefore still classified, which is exactly the point.
     *
     * It is a best-effort classifier for our own shim's output, NOT an adversarial parser. Anything
     * it cannot read — no name key, a name beyond the window, an escaped name literal, a name it does
     * not recognise — yields `null`, i.e. today's behaviour. Fail-open is deliberate: a fail-closed
     * sniff would let a future shim change silently strand the reader, and it would be defending a
     * boundary the bundle patch and the origin gate already hold.
     */
    fun rawCeilingFor(raw: String): Int? = RAW_CEILINGS[sniffName(raw)]

    /** True iff [raw] is within its name's ceiling (or its name is uncapped). */
    fun withinRawCeiling(raw: String): Boolean {
        val ceiling = rawCeilingFor(raw) ?: return true
        return raw.length <= ceiling
    }

    /**
     * The SINGLE admission decision the bridge's web-message listener runs, before
     * [FoliateMessageParser.parse] is reached: trusted origin AND within the raw ceiling.
     *
     * Composed here rather than inlined at the listener so the JVM test pins the exact predicate
     * production evaluates (the `foliateSetStylesJs` seam pattern — no test-vs-production drift).
     * A rejected message is dropped silently, exactly like an unparseable one.
     */
    fun admitsMessage(sourceOrigin: String?, isMainFrame: Boolean, raw: String): Boolean =
        isTrustedMessage(sourceOrigin, isMainFrame) && withinRawCeiling(raw)

    /**
     * The message name read LEXICALLY from the head of [raw], or null when it cannot be read within
     * [NAME_SNIFF_WINDOW] characters. Bails on a backslash rather than decoding escapes: no name this
     * feature caps contains one, and "unrecognised" is the safe answer.
     *
     * `"name"` must be the FIRST key of the top-level object — not merely the first one that appears.
     * Scanning for any `"name"` would let a payload shaped `{"detail":{"name":"book-ready"},
     * "name":"selection"}` be classified from the NESTED key while the parser reads the top-level one,
     * i.e. a decoy could pick the classification in EITHER direction, including loosening a capped
     * message to uncapped. Anchoring to the first key removes that whole class, costs nothing (the
     * shim always emits `name` first), and degrades any other ordering to null = uncapped = today's
     * behaviour.
     */
    private fun sniffName(raw: String): String? {
        val window = if (raw.length <= NAME_SNIFF_WINDOW) raw else raw.substring(0, NAME_SNIFF_WINDOW)
        var i = 0

        i = skipJsonWhitespace(window, i)
        if (i >= window.length || window[i] != '{') return null
        i = skipJsonWhitespace(window, i + 1)
        if (!window.startsWith(NAME_KEY, i)) return null

        i = skipJsonWhitespace(window, i + NAME_KEY.length)
        if (i >= window.length || window[i] != ':') return null
        i = skipJsonWhitespace(window, i + 1)
        if (i >= window.length || window[i] != '"') return null
        i++

        val start = i
        while (i < window.length) {
            when (window[i]) {
                '\\' -> return null // an escaped literal — not a name this feature caps
                '"' -> return window.substring(start, i)
                else -> i++
            }
        }
        return null // the closing quote lies beyond the sniff window
    }

    /** JSON's whitespace set (RFC 8259 §2: space, tab, LF, CR) — deliberately NOT Kotlin's
     *  `Char.isWhitespace()`, which also accepts NBSP and other Unicode spaces JSON does not. */
    private fun skipJsonWhitespace(s: String, from: Int): Int {
        var i = from
        while (i < s.length) {
            val c = s[i].code
            if (c != 0x20 && c != 0x09 && c != 0x0A && c != 0x0D) break
            i++
        }
        return i
    }

    /** True iff [url] is on the trusted shell origin (exact, or a path under it). The leading-`/`
     *  guard prevents a sibling-host bypass (`…androidplatform.net.evil.com`). */
    fun isSameOrigin(url: String?): Boolean =
        url != null && (url == SHELL_ORIGIN || url.startsWith("$SHELL_ORIGIN/"))

    /** Allow MAIN-FRAME navigation only WITHIN the shell origin; block `javascript:`, off-origin,
     *  `data:`, top-level `blob:` navs, `target=_blank` to remote, etc. (Sub-frame `blob:` section
     *  documents are allowed by the bridge — they are required for rendering.) */
    fun isAllowedNavigation(url: String?): Boolean = isSameOrigin(url)

    /**
     * Block any resource request that is NOT same-origin and IS an http(s) load — remote `img` /
     * CSS `url()` / font / media / sub-frame the book HTML might trigger WITHOUT script (the passive
     * exfil/tracking surface Gate-4 round 3 flagged). Same-origin (`/assets`, `/book`) is served by
     * the loader; `blob:`/`data:` are handled by the WebView internally and never reach here.
     */
    fun shouldBlockRequest(url: String?): Boolean {
        if (url == null) return false
        if (isSameOrigin(url)) return false
        val lower = url.lowercase()
        return lower.startsWith("http://") || lower.startsWith("https://")
    }
}
