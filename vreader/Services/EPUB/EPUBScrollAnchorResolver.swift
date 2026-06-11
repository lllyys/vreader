// Purpose: Feature #85 WI-1 — resolve a saved reading position's href to a
// legacy continuous-scroll spine anchor index, tolerant of container-relative
// vs OPF-relative href forms. With approach C the SAME book uses Readium
// (paged) and the legacy #71 stitch (scroll); a Readium session may persist a
// container-relative href (e.g. "OEBPS/ch1.html") while the legacy spine items
// are OPF-relative ("ch1.html"). An exact-match-only lookup would miss and
// restart scroll mode at the book top (Gate-2 High). This resolver matches
// exactly first, then on a path-COMPONENT boundary suffix either direction.
//
// @coordinates-with: EPUBReaderContainerView.swift (buildContinuousScrollConfig),
//   EPUBFileLoader.swift (restorePosition — Bug #349)

import Foundation

enum EPUBScrollAnchorResolver {

    /// The spine index to anchor the continuous-scroll window on for a saved
    /// position href, or `0` (book top) when there is no href / no match.
    ///
    /// - Parameters:
    ///   - storedHref: the saved position's href (may be container- or
    ///     OPF-relative, depending on which engine wrote it).
    ///   - spineHrefs: the legacy parser's spine hrefs, in reading order.
    static func anchorIndex(forStoredHref storedHref: String?, spineHrefs: [String]) -> Int {
        matchIndex(forStoredHref: storedHref, spineHrefs: spineHrefs) ?? 0
    }

    /// Bug #349: the nil-on-miss variant — `EPUBFileLoader.restorePosition`
    /// needs to DISTINGUISH "no match" (fall back to the first spine item)
    /// from "matched spine 0", which the 0-default conflates.
    static func matchIndex(forStoredHref storedHref: String?, spineHrefs: [String]) -> Int? {
        guard var href = storedHref, !href.isEmpty else { return nil }
        // Bug #349 (audit r1): the saved href may carry a FRAGMENT
        // ("ch1.xhtml#p12" — the Readium dual-write stores the locator href
        // verbatim); spine hrefs never do. Match fragment-insensitively.
        if let hash = href.firstIndex(of: "#") { href = String(href[..<hash]) }
        guard !href.isEmpty else { return nil }
        // 1) Exact match (same engine wrote + reads, or already-normalized).
        if let i = spineHrefs.firstIndex(of: href) { return i }
        // 2) Path-component-boundary suffix match either direction, so
        //    "OEBPS/ch1.html" resolves to spine "ch1.html" (and vice versa)
        //    WITHOUT "intro_ch1.html" matching "ch1.html" (the leading "/" pins
        //    a full path component).
        if let i = spineHrefs.firstIndex(where: {
            !$0.isEmpty && (href.hasSuffix("/" + $0) || $0.hasSuffix("/" + href))
        }) {
            return i
        }
        // 3) Bug #349: percent-encoding-normalized retry. Readium persists
        //    URL-form hrefs ("%E7%AC%AC...xhtml" for CJK filenames) while the
        //    legacy parser's spine hrefs are decoded ("第...xhtml") — the
        //    exact + suffix passes above miss, and the saved position silently
        //    fell back to the cover. Decode both sides and re-run both rules —
        //    requiring a UNIQUE match (audit r1 Medium: decoding can collapse
        //    distinct manifest entries like "a%2Fb.xhtml" / "a/b.xhtml" onto
        //    one string; guessing `firstIndex` would restore the wrong
        //    chapter — ambiguity falls back instead).
        let decoded = href.removingPercentEncoding ?? href
        let decodedSpine = spineHrefs.map { $0.removingPercentEncoding ?? $0 }
        if decoded != href || decodedSpine != spineHrefs {
            let exact = decodedSpine.indices.filter { decodedSpine[$0] == decoded }
            if exact.count == 1 { return exact[0] }
            if exact.isEmpty {
                let suffix = decodedSpine.indices.filter {
                    let s = decodedSpine[$0]
                    return !s.isEmpty && (decoded.hasSuffix("/" + s) || s.hasSuffix("/" + decoded))
                }
                if suffix.count == 1 { return suffix[0] }
            }
        }
        return nil
    }
}
