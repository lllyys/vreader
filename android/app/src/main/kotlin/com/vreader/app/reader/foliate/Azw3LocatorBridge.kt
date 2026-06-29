// Purpose: map a foliate `relocate` event into the engine-neutral [VReaderLocator] the app persists,
// mirroring ReadiumLocatorBridge. Foliate's CFI is platform-local (lossy cross-platform), so the
// canonical resume anchor is `progression`; the CFI rides along in `legacyLocator.cfi` for precise
// SAME-platform restore. Uses VReaderLocator.wrapLegacy (the `epubWKWebView` legacy engine) — NO new
// contract enum (Gate-2 decision). String fields are NFC-normalized downstream by the canonical layer
// (Identity.canonicalJson), so they're stored verbatim here (the ReadiumLocatorBridge pattern).
// Feature #126 WI-5.
package com.vreader.app.reader.foliate

import vreader.contracts.BookFormat
import vreader.contracts.Locator
import vreader.contracts.VReaderLocator

object Azw3LocatorBridge {

    /**
     * Build the persistable envelope for a foliate position. [contentSHA256]/[fileByteCount] supply
     * the book identity foliate's event omits. A non-finite fraction is dropped (it would make the
     * canonical locator invalid); a null/blank CFI is omitted.
     */
    fun toEnvelope(
        relocate: FoliateMessage.Relocate,
        contentSHA256: String,
        fileByteCount: Long,
    ): VReaderLocator {
        val locator = Locator(
            contentSHA256 = contentSHA256,
            fileByteCount = fileByteCount,
            format = BookFormat.azw3.name,
            progression = relocate.fraction?.takeIf { it.isFinite() },
            cfi = relocate.cfi?.takeIf { it.isNotBlank() },
        )
        return VReaderLocator.wrapLegacy(locator)
    }
}
