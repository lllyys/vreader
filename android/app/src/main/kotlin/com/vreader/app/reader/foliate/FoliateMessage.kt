// Purpose: typed events the Android Foliate (AZW3/MOBI/KF8) reader receives from the foliate-js
// bundle running in a WebView. The bundle posts `{name, detail}` JSON over the bridge (the iOS
// `window.webkit.messageHandlers[name].postMessage` calls, forwarded by the Android shell shim to
// `addWebMessageListener`'s `vreaderHost`). FoliateMessageParser turns that wire JSON into these.
// Mirrors the iOS FoliateMessageParser contract. Feature #126 WI-2.
package com.vreader.app.reader.foliate

/** A parsed event from the foliate-js bundle. Only the messages the MVP reader consumes are typed;
 *  everything else (selection/tap/tts/search/…) maps to [Other] and is ignored by the reader. */
sealed interface FoliateMessage {

    /** The bundle loaded and `window.readerAPI` is available — safe to call `open`/`init`. */
    data object BridgeReady : FoliateMessage

    /** The book parsed; metadata is available. `sectionTotal` is the spine length (> 0 when real). */
    data class BookReady(val title: String?, val sectionTotal: Int) : FoliateMessage

    /** Reading position changed. `cfi` is foliate's platform-local CFI (lossy cross-platform);
     *  `fraction` is the 0..1 progress (the canonical resume anchor). */
    data class Relocate(
        val cfi: String?,
        val fraction: Double?,
        val sectionIndex: Int,
        val sectionTotal: Int,
    ) : FoliateMessage

    /** A JS-side error (bundle init failure, open failure, unhandled rejection). */
    data class Error(val message: String, val type: String?) : FoliateMessage

    /** A recognized-but-unconsumed event name (selection, tap, tts-*, search-*, …). */
    data class Other(val name: String) : FoliateMessage
}
