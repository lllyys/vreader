// Purpose: the PURE security decisions for the AZW3/foliate reader WebView, extracted from
// FoliateBridge so they are fully JVM-unit-testable (no WebView). Three boundaries, all keyed to the
// single trusted shell origin: which bridge messages to trust, which navigations to allow, and which
// resource requests to block (passive-exfil defense). Feature #126 WI-3.
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
