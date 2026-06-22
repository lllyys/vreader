// Purpose: feature #117 WI-1 (#110 Phase 3) — OPDS 1.2 catalog value types, mirroring the iOS
// `OPDSModels.swift` (Feed/Entry/Link + acquisition/navigation relations + relative-URL
// resolution). Pure value types; no Android deps. The browse/add UI is design-gated (#1799) —
// these models back the parser + acquisition pipeline only.
package com.vreader.app.opds

import java.net.URI

/** Which OPDS acquisition relation a link is — only [generic]/[openAccess] auto-import in v1.
 *  [unsupported] = an acquisition rel we don't recognise (an unknown sub-rel / indirect) — it is
 *  an acquisition but must NOT auto-import (could be auth/payment/lending). */
enum class AcquisitionKind { generic, openAccess, buy, borrow, sample, subscribe, unsupported, none }

/** A link element from an OPDS feed (feed-level or entry-level). */
data class OpdsLink(
    val rel: String?,
    val href: String,
    val type: String?,
    val title: String? = null,
) {
    // Exact prefix or a `/`-delimited sub-rel only — so `…/acquisitionXYZ` is NOT an acquisition.
    val isAcquisition: Boolean get() = rel == ACQ_PREFIX || rel?.startsWith("$ACQ_PREFIX/") == true

    /** The acquisition relation kind. v1 auto-imports ONLY [generic] + [openAccess]; everything
     *  else (buy/borrow/sample/subscribe + any UNKNOWN sub-rel → [unsupported]) requires
     *  UI/auth/payment that doesn't exist yet and must not auto-import. */
    val acquisitionKind: AcquisitionKind
        get() = when (rel) {
            null -> AcquisitionKind.none
            ACQ_PREFIX -> AcquisitionKind.generic
            "$ACQ_PREFIX/open-access" -> AcquisitionKind.openAccess
            "$ACQ_PREFIX/buy" -> AcquisitionKind.buy
            "$ACQ_PREFIX/borrow" -> AcquisitionKind.borrow
            "$ACQ_PREFIX/sample", "$ACQ_PREFIX/preview" -> AcquisitionKind.sample
            "$ACQ_PREFIX/subscribe" -> AcquisitionKind.subscribe
            else -> if (isAcquisition) AcquisitionKind.unsupported else AcquisitionKind.none
        }

    val isAutoImportable: Boolean
        get() = acquisitionKind == AcquisitionKind.generic || acquisitionKind == AcquisitionKind.openAccess

    /** Canonical file extension from the MIME [type], or null if unsupported/absent. */
    val formatExtension: String?
        get() = when {
            type == null -> null
            type.contains("epub") -> "epub"
            type.contains("pdf") -> "pdf"
            type.contains("mobi") || type.contains("x-mobipocket") -> "azw3"
            else -> null
        }

    /** Resolve [href] against [baseUrl]: absolute hrefs pass through; relative resolve against base. */
    fun resolvedHref(baseUrl: String?): String? = resolveAgainst(href, baseUrl)
}

/** A single entry — a book (acquisition links) or a navigation category. */
data class OpdsEntry(
    val title: String,
    val id: String,
    val author: String? = null,
    val summary: String? = null,
    val updated: String? = null,
    val links: List<OpdsLink> = emptyList(),
) {
    val acquisitionLinks: List<OpdsLink> get() = links.filter { it.isAcquisition }

    /** Cover/thumbnail URL, if any. */
    fun coverUrl(baseUrl: String?): String? = links.firstOrNull {
        it.rel == "http://opds-spec.org/image" || it.rel == "http://opds-spec.org/image/thumbnail"
    }?.resolvedHref(baseUrl)

    /** Navigation target (browse into a sub-feed): an atom+xml link that isn't an acquisition. */
    fun navigationUrl(baseUrl: String?): String? = links.firstOrNull {
        !it.isAcquisition && (it.rel == null || it.rel == "subsection" ||
            it.rel?.startsWith("http://opds-spec.org/sort/") == true ||
            it.type?.contains("atom+xml") == true)
    }?.resolvedHref(baseUrl)
}

enum class OpdsFeedKind { navigation, acquisition }

/** An OPDS catalog feed parsed from Atom XML. */
data class OpdsFeed(
    val title: String,
    val id: String,
    val links: List<OpdsLink> = emptyList(),
    val entries: List<OpdsEntry> = emptyList(),
    val baseUrl: String? = null,
) {
    /** Acquisition if any entry has an acquisition link, else navigation. */
    val kind: OpdsFeedKind
        get() = if (entries.any { it.acquisitionLinks.isNotEmpty() }) OpdsFeedKind.acquisition
        else OpdsFeedKind.navigation

    val nextPageUrl: String? get() = links.firstOrNull { it.rel == "next" }?.resolvedHref(baseUrl)

    val searchUrl: String?
        get() = links.firstOrNull {
            it.rel == "search" && it.type?.contains("opensearchdescription") == true
        }?.resolvedHref(baseUrl)

    companion object {
        /** Dedup entries by id, first occurrence wins (mirrors iOS `OPDSFeed.deduplicated`). */
        fun dedupe(entries: List<OpdsEntry>): List<OpdsEntry> {
            val seen = HashSet<String>()
            return entries.filter { it.id.isEmpty() || seen.add(it.id) }
        }
    }
}

/** OPDS backend errors (parse / network / acquisition). Mirrors iOS `OPDSParserError` + acquisition. */
sealed class OpdsError(message: String) : Exception(message) {
    class InvalidXml(detail: String) : OpdsError("invalid OPDS feed: $detail")
    object EmptyData : OpdsError("the server returned an empty response")
    class Network(detail: String) : OpdsError("network error: $detail")
    class Http(val code: Int) : OpdsError("HTTP $code")
    class InvalidUrl(url: String) : OpdsError("invalid URL: $url")
    class UnsupportedAcquisition(detail: String) : OpdsError("no importable acquisition: $detail")
    class NotABook(detail: String) : OpdsError("download is not a supported book: $detail")
}

private const val ACQ_PREFIX = "http://opds-spec.org/acquisition"

/** Absolute href passes through; relative resolves against [baseUrl] via java.net.URI. */
internal fun resolveAgainst(href: String, baseUrl: String?): String? {
    val h = href.trim()
    if (h.isEmpty()) return null
    val asUri = runCatching { URI(h) }.getOrNull()
    if (asUri?.isAbsolute == true) return h  // already has a scheme
    if (baseUrl == null) return h
    val base = runCatching { URI(baseUrl) }.getOrNull() ?: return h
    return runCatching {
        when {
            // Query-/fragment-only references resolve against the base's FULL path (preserving e.g.
            // `root.xml`), not its directory — `URI.resolve` would drop the filename.
            h.startsWith("?") -> URI(base.scheme, base.authority, base.path, h.substring(1), base.fragment).toString()
            h.startsWith("#") -> URI(base.scheme, base.authority, base.path, base.query, h.substring(1)).toString()
            else -> base.resolve(h).toString()
        }
    }.getOrNull()
}
