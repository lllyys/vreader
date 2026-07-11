// Purpose: feature #134 WI-1 — the Book Details sheet's UI model (the metadata the sheet shows).
// A pure value type with NO Compose/Android UI deps (rule 50 boundary). Mirrors the iOS
// BookDetailsViewModel's mapped fields. Intentionally carries NO `year` and NO `coverPath`: Android
// has no data source for either (even iOS never maps year), so those rows are OMITTED, never invented
// (the plan's §details-source absence invariant). Optional fields are null when the source is absent
// so the sheet omits the corresponding row (author/pages/location/tags).
package com.vreader.app.reader.details

/**
 * The assembled metadata for the Book Details sheet.
 *
 * @property title the book title (always present).
 * @property author the book author, or null when unknown → the author line is omitted.
 * @property tags the book's collection names (empty when it belongs to none → the tag row is omitted).
 * @property formatLabel a display label for the file format (e.g. "EPUB", "Markdown").
 * @property sizeLabel a human-readable file size, or "Unknown" for a 0/negative byte count.
 * @property pagesLabel the page count label, non-null ONLY when a page count is supplied (PDF).
 * @property fingerprintDisplay the middle-truncated canonical key (for display).
 * @property fingerprintFull the FULL canonical fingerprint key (the copy-button payload).
 * @property locationLabel a truthful relative location ("Books/<name>"), or null when no local file.
 */
data class BookDetailsUiModel(
    val title: String,
    val author: String?,
    val tags: List<String>,
    val formatLabel: String,
    val sizeLabel: String,
    val pagesLabel: String?,
    val fingerprintDisplay: String,
    val fingerprintFull: String,
    val locationLabel: String?,
)
