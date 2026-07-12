// Purpose: feature #131 WI-1 — the stable per-unit identity for a bilingual
// translation unit. `storageKey` is the persistence key for a cached chapter
// translation ("${kind.name}:$value"). The Kind enumerates the addressable
// "translation unit" per format: EPUB/Foliate chapters address by href; TXT/MD
// address a document-global segment-window index (the doc is a single flat
// stream, windowed for translation); PDF addresses a page range.
//
// @coordinates-with: dev-docs/plans/20260710-feature-131-android-bilingual.md (WI-1)
package com.vreader.app.bilingual

/**
 * Identifies a single translation unit for caching. [storageKey] is the durable
 * key ("${kind.name}:$value").
 */
data class TranslationUnitId(val kind: Kind, val value: String) {

    /** The persistence key: the kind's name, a colon, then the raw value. */
    val storageKey: String get() = "${kind.name}:$value"

    enum class Kind {
        epubHref,
        foliateHref,
        txtDocSegmentWindow,
        mdDocSegmentWindow,
        pdfPageRange,
    }
}
