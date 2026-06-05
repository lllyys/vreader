// Purpose: Feature #85 WI-1 — resolve a saved reading position's href to a
// legacy continuous-scroll spine anchor index, tolerant of container-relative
// vs OPF-relative href forms. With approach C the SAME book uses Readium
// (paged) and the legacy #71 stitch (scroll); a Readium session may persist a
// container-relative href (e.g. "OEBPS/ch1.html") while the legacy spine items
// are OPF-relative ("ch1.html"). An exact-match-only lookup would miss and
// restart scroll mode at the book top (Gate-2 High). This resolver matches
// exactly first, then on a path-COMPONENT boundary suffix either direction.
//
// @coordinates-with: EPUBReaderContainerView.swift (buildContinuousScrollConfig)

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
        guard let href = storedHref, !href.isEmpty else { return 0 }
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
        return 0
    }
}
