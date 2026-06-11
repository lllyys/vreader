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

// MARK: - Bug #349: percent-encoding tolerance + the nil-on-miss variant

@Suite("EPUBScrollAnchorResolver — bug #349 additions")
struct EPUBScrollAnchorResolverBug349Tests {

    @Test func percentEncodedSavedHrefMatchesDecodedSpine() {
        let spine = ["封面.xhtml", "第一章.xhtml", "第二章.xhtml"]
        let encoded = "第二章.xhtml".addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed)!
        #expect(EPUBScrollAnchorResolver.anchorIndex(
            forStoredHref: encoded, spineHrefs: spine) == 2)
    }

    @Test func encodedContainerRelativeMatchesDecodedSpineSuffix() {
        let spine = ["第一章.xhtml"]
        let encoded = ("OEBPS/" + "第一章.xhtml").addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed)!
        #expect(EPUBScrollAnchorResolver.anchorIndex(
            forStoredHref: encoded, spineHrefs: spine) == 0)
    }

    @Test func matchIndexDistinguishesMissFromSpineZero() {
        let spine = ["cover.xhtml", "ch1.xhtml"]
        #expect(EPUBScrollAnchorResolver.matchIndex(
            forStoredHref: "cover.xhtml", spineHrefs: spine) == 0)
        #expect(EPUBScrollAnchorResolver.matchIndex(
            forStoredHref: "missing.xhtml", spineHrefs: spine) == nil)
        #expect(EPUBScrollAnchorResolver.matchIndex(
            forStoredHref: nil, spineHrefs: spine) == nil)
    }
}

// MARK: - Bug #349 audit r1: fragments + decoded-ambiguity fallback

@Suite("EPUBScrollAnchorResolver — fragments + ambiguity (bug #349 r1)")
struct EPUBScrollAnchorResolverFragmentTests {

    @Test func fragmentBearingSavedHrefMatches() {
        let spine = ["cover.xhtml", "ch1.xhtml"]
        #expect(EPUBScrollAnchorResolver.matchIndex(
            forStoredHref: "ch1.xhtml#p12", spineHrefs: spine) == 1)
        #expect(EPUBScrollAnchorResolver.matchIndex(
            forStoredHref: "OEBPS/ch1.xhtml#frag", spineHrefs: spine) == 1)
    }

    @Test func encodedCJKWithFragmentMatches() {
        let spine = ["第一章.xhtml"]
        let encoded = "第一章.xhtml".addingPercentEncoding(
            withAllowedCharacters: .urlPathAllowed)! + "#loc"
        #expect(EPUBScrollAnchorResolver.matchIndex(
            forStoredHref: encoded, spineHrefs: spine) == 0)
    }

    @Test func decodedCollisionFallsBackInsteadOfGuessing() {
        // Two legal-but-distinct manifest entries collapse to the same
        // decoded string — the resolver must NOT pick one arbitrarily.
        let spine = ["a%2Fb.xhtml", "a/b.xhtml"]
        #expect(EPUBScrollAnchorResolver.matchIndex(
            forStoredHref: "a%2fb.xhtml", spineHrefs: spine) == nil)
    }
}
