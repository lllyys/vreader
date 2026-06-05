// Purpose: Feature #85 WI-1 — pin the cross-engine href→anchor resolution for
// the legacy continuous-scroll path. A Readium (paged) session may persist a
// container-relative href while the legacy spine is OPF-relative; the resolver
// must still land on the right chapter (Gate-2 High), without a too-loose
// suffix match grabbing the wrong chapter.
//
// @coordinates-with: EPUBScrollAnchorResolver.swift

import Testing
@testable import vreader

@Suite("Feature #85 WI-1 — EPUBScrollAnchorResolver")
struct EPUBScrollAnchorResolverTests {

    private let spine = ["ch1.html", "ch2.html", "ch3.html"]

    @Test func exactMatch() {
        #expect(EPUBScrollAnchorResolver.anchorIndex(forStoredHref: "ch2.html", spineHrefs: spine) == 1)
    }

    @Test func containerRelativeHrefResolvesToOPFSpine() {
        #expect(EPUBScrollAnchorResolver.anchorIndex(
            forStoredHref: "OEBPS/ch3.html", spineHrefs: spine) == 2)
    }

    @Test func opfHrefResolvesToContainerSpine() {
        let containerSpine = ["OEBPS/ch1.html", "OEBPS/ch2.html"]
        #expect(EPUBScrollAnchorResolver.anchorIndex(
            forStoredHref: "ch2.html", spineHrefs: containerSpine) == 1)
    }

    @Test func partialFilenameDoesNotFalseMatch() {
        let s = ["intro_ch1.html", "ch1.html"]
        #expect(EPUBScrollAnchorResolver.anchorIndex(
            forStoredHref: "OEBPS/ch1.html", spineHrefs: s) == 1)
    }

    @Test func noMatchReturnsBookTop() {
        #expect(EPUBScrollAnchorResolver.anchorIndex(
            forStoredHref: "nonexistent.html", spineHrefs: spine) == 0)
    }

    @Test(arguments: [nil, ""])
    func nilOrEmptyHrefReturnsBookTop(href: String?) {
        #expect(EPUBScrollAnchorResolver.anchorIndex(forStoredHref: href, spineHrefs: spine) == 0)
    }

    @Test func emptySpineReturnsBookTop() {
        #expect(EPUBScrollAnchorResolver.anchorIndex(forStoredHref: "ch1.html", spineHrefs: []) == 0)
    }

    @Test func nestedPathResolves() {
        let nested = ["text/ch1.xhtml", "text/ch2.xhtml"]
        #expect(EPUBScrollAnchorResolver.anchorIndex(
            forStoredHref: "OEBPS/text/ch2.xhtml", spineHrefs: nested) == 1)
    }
}
