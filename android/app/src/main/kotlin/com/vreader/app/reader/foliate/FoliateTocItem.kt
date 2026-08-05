// Purpose: the wire shape of one node in the foliate-js table of contents. `serializeTOC`
// (foliate-bundle.js) emits a recursive `{label, href, subitems}` tree on every `book-ready`; this
// is its typed Kotlin mirror, produced by [FoliateTocParser] and consumed by the AZW3 TOC provider.
// Deliberately dumb: values are carried VERBATIM (no trim, no blank filtering, no href
// normalization) because the display/navigation policy — iOS #38's trim + skip-blank-but-recurse —
// belongs to the provider, and href matching downstream is byte-exact. Feature #140 WI-1.
package com.vreader.app.reader.foliate

/**
 * One table-of-contents node as the foliate-js bundle serialized it.
 *
 * @param label the chapter title exactly as authored — may be empty, blank, or contain newlines.
 * @param href foliate's own opaque navigation target — an EPUB-relative path (possibly with a
 *   `#fragment`, a query, or non-ASCII characters), a KF8 `kindle:pos:fid:…:off:…` URI, or a MOBI6
 *   `filepos:NNNN`. Never rewritten: `relocate.tocHref` is matched against it byte-exactly.
 * @param subitems nested children, parent-before-children order preserved from the wire.
 */
data class FoliateTocItem(
    val label: String,
    val href: String,
    val subitems: List<FoliateTocItem> = emptyList(),
)
