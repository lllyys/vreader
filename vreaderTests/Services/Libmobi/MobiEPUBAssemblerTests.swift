// Feature #42 Phase 2 WI-2b: the deterministic EPUB-assembly core. All cases are
// CI-safe — they build synthetic MobiParts (no libmobi parse) and assert the
// resulting EPUB file layout: mimetype-first/stored, a well-formed container.xml
// + content.opf (manifest covers every part + nav, spine is markup in decode
// order), part bytes at the manifest hrefs, XML-escaped title, deterministic +
// content-addressed identity.

import Testing
import Foundation
@testable import vreader

@Suite("MOBI→EPUB assembler (Feature #42 Phase 2 WI-2b)")
struct MobiEPUBAssemblerTests {

    private func part(_ section: MobiPart.Section, _ uid: Int, _ ext: String, _ body: String) -> MobiPart {
        MobiPart(section: section, uid: uid, fileExtension: ext, data: Data(body.utf8))
    }

    private var sampleParts: [MobiPart] {
        [
            part(.markup, 0, "html", "<html><body><p>Chapter 1</p></body></html>"),
            part(.markup, 1, "html", "<html><body><p>Chapter 2</p></body></html>"),
            part(.flow, 0, "css", "p { margin: 1em; }"),
            part(.resource, 0, "jpg", "pretend-jpeg-bytes"),
        ]
    }

    @Test("mimetype is first, stored, exactly application/epub+zip; nothing else stored")
    func mimetypeFirstStored() throws {
        let files = (try MobiEPUBAssembler.assemble(parts: sampleParts, title: "T"))
        #expect(files.first?.path == "mimetype")
        #expect(files.first?.isStored == true)
        #expect(String(decoding: files[0].data, as: UTF8.self) == "application/epub+zip")
        #expect(files.dropFirst().allSatisfy { !$0.isStored })
    }

    @Test("container.xml points at OEBPS/content.opf and is well-formed XML")
    func containerXMLValid() throws {
        let files = (try MobiEPUBAssembler.assemble(parts: sampleParts, title: "T"))
        let container = try #require(files.first { $0.path == "META-INF/container.xml" })
        let s = String(decoding: container.data, as: UTF8.self)
        #expect(s.contains("full-path=\"OEBPS/content.opf\""))
        #expect(isWellFormedXML(container.data))
    }

    // Bug #336 reopen: the source MOBI's language threads into dc:language so
    // language-gated rendering (CJK flush-justify) works on converted books.
    @Test("content.opf carries the threaded dc:language; nil/empty falls back to und")
    func opfLanguageThreading() throws {
        let zh = try MobiEPUBAssembler.assemble(parts: sampleParts, title: "T", language: "zh-cn")
        let zhOPF = try #require(zh.first { $0.path == "OEBPS/content.opf" })
        #expect(String(decoding: zhOPF.data, as: UTF8.self).contains("<dc:language>zh-cn</dc:language>"))

        let none = try MobiEPUBAssembler.assemble(parts: sampleParts, title: "T")
        let noneOPF = try #require(none.first { $0.path == "OEBPS/content.opf" })
        #expect(String(decoding: noneOPF.data, as: UTF8.self).contains("<dc:language>und</dc:language>"))

        let empty = try MobiEPUBAssembler.assemble(parts: sampleParts, title: "T", language: "")
        let emptyOPF = try #require(empty.first { $0.path == "OEBPS/content.opf" })
        #expect(String(decoding: emptyOPF.data, as: UTF8.self).contains("<dc:language>und</dc:language>"))
    }

    @Test("content.opf manifests every part + nav, spine is markup in decode order")
    func opfManifestAndSpine() throws {
        let files = (try MobiEPUBAssembler.assemble(parts: sampleParts, title: "T"))
        let opf = try #require(files.first { $0.path == "OEBPS/content.opf" })
        let s = String(decoding: opf.data, as: UTF8.self)
        #expect(isWellFormedXML(opf.data))
        #expect(s.contains("href=\"text/part0000.xhtml\" media-type=\"application/xhtml+xml\""))
        #expect(s.contains("href=\"text/part0001.xhtml\""))
        #expect(s.contains("href=\"styles/flow0000.css\" media-type=\"text/css\""))
        #expect(s.contains("href=\"resources/res0000.jpg\" media-type=\"image/jpeg\""))
        #expect(s.contains("properties=\"nav\""))
        let spine = s.range(of: "<spine>").map { String(s[$0.upperBound...]) } ?? ""
        let r0 = try #require(spine.range(of: "idref=\"html0000\""))
        let r1 = try #require(spine.range(of: "idref=\"html0001\""))
        #expect(r0.lowerBound < r1.lowerBound, "spine order must follow decode order")
    }

    @Test("part bytes land at the manifest hrefs; nav present")
    func partFilesPresent() throws {
        let files = (try MobiEPUBAssembler.assemble(parts: sampleParts, title: "T"))
        let p0 = try #require(files.first { $0.path == "OEBPS/text/part0000.xhtml" })
        #expect(String(decoding: p0.data, as: UTF8.self).contains("Chapter 1"))
        let css = try #require(files.first { $0.path == "OEBPS/styles/flow0000.css" })
        #expect(String(decoding: css.data, as: UTF8.self).contains("margin"))
        #expect(files.contains { $0.path == "OEBPS/resources/res0000.jpg" })
        #expect(files.contains { $0.path == "OEBPS/nav.xhtml" })
    }

    @Test("all five XML entities are escaped in BOTH content.opf and nav.xhtml")
    func titleEscapedEverywhere() throws {
        let nasty = "A & B < C > D \" E ' F"
        let files = try MobiEPUBAssembler.assemble(parts: sampleParts, title: nasty)
        for path in ["OEBPS/content.opf", "OEBPS/nav.xhtml"] {
            let file = try #require(files.first { $0.path == path })
            let s = String(decoding: file.data, as: UTF8.self)
            #expect(s.contains("&amp;"))
            #expect(s.contains("&lt;"))
            #expect(s.contains("&gt;"))
            #expect(s.contains("&quot;"))
            #expect(s.contains("&apos;"))
            // The raw, un-escaped title must not appear verbatim.
            #expect(!s.contains(nasty))
            // And the document stays well-formed after escaping.
            #expect(isWellFormedXML(file.data))
        }
    }

    @Test("assembly is deterministic — same parts yield byte-identical output")
    func deterministic() throws {
        #expect((try MobiEPUBAssembler.assemble(parts: sampleParts, title: "T"))
                == (try MobiEPUBAssembler.assemble(parts: sampleParts, title: "T")))
    }

    @Test("package id depends on structure, not just bytes (section/uid/ext)")
    func idDependsOnStructureNotJustBytes() throws {
        // Same payload bytes, different section → must NOT collide on one id.
        let a = idFromOPF(try MobiEPUBAssembler.assemble(
            parts: [part(.markup, 0, "html", "<html/>"), part(.flow, 0, "css", "X")], title: "T"))
        let b = idFromOPF(try MobiEPUBAssembler.assemble(
            parts: [part(.markup, 0, "html", "<html/>"), part(.flow, 0, "css", "Y")], title: "T"))
        let c = idFromOPF(try MobiEPUBAssembler.assemble(
            parts: [part(.markup, 0, "html", "<html/>"), part(.flow, 1, "css", "X")], title: "T"))
        #expect(a != b, "different flow bytes → different id")
        #expect(a != c, "different uid (same bytes) → different id")
    }

    @Test("zero markup is rejected with .noMarkup (invalid empty spine/TOC)")
    func zeroMarkupThrows() {
        let resourceOnly = [part(.resource, 0, "png", "img")]
        #expect(throws: MobiEPUBError.noMarkup) {
            _ = try MobiEPUBAssembler.assemble(parts: resourceOnly, title: "T")
        }
    }

    @Test("nav.xhtml is well-formed and has one <li> per markup part")
    func navStructure() throws {
        let files = try MobiEPUBAssembler.assemble(parts: sampleParts, title: "T")
        let nav = try #require(files.first { $0.path == "OEBPS/nav.xhtml" })
        #expect(isWellFormedXML(nav.data))
        let s = String(decoding: nav.data, as: UTF8.self)
        // sampleParts has 2 markup parts → 2 <li>.
        #expect(s.components(separatedBy: "<li>").count - 1 == 2)
    }

    // MARK: WI-4a — self-describing OPF (author + cover)

    @Test("author → dc:creator; first image resource → cover (meta + property)")
    func selfDescribingOPF() throws {
        // sampleParts has a jpg resource at res0000 → it becomes the cover.
        let files = try MobiEPUBAssembler.assemble(parts: sampleParts, title: "T", author: "Jane Doe")
        let opf = try #require(files.first { $0.path == "OEBPS/content.opf" })
        let s = String(decoding: opf.data, as: UTF8.self)
        #expect(isWellFormedXML(opf.data))
        #expect(s.contains("<dc:creator>Jane Doe</dc:creator>"))
        #expect(s.contains("<meta name=\"cover\" content=\"res0000\"/>"))
        #expect(s.contains("properties=\"cover-image\""))
    }

    @Test("no author + no image resource → no dc:creator, no cover meta")
    func noAuthorNoCover() throws {
        let files = try MobiEPUBAssembler.assemble(
            parts: [part(.markup, 0, "html", "<html><body><p>x</p></body></html>")], title: "T")
        let opf = try #require(files.first { $0.path == "OEBPS/content.opf" })
        let s = String(decoding: opf.data, as: UTF8.self)
        #expect(isWellFormedXML(opf.data))
        #expect(!s.contains("dc:creator"))
        #expect(!s.contains("name=\"cover\""))
    }

    @Test("author is XML-escaped in dc:creator")
    func authorEscaped() throws {
        let files = try MobiEPUBAssembler.assemble(parts: sampleParts, title: "T", author: "A & B <c>")
        let opf = try #require(files.first { $0.path == "OEBPS/content.opf" })
        #expect(isWellFormedXML(opf.data))
        let s = String(decoding: opf.data, as: UTF8.self)
        #expect(s.contains("<dc:creator>A &amp; B &lt;c&gt;</dc:creator>"))
    }

    // MARK: helpers

    private func isWellFormedXML(_ data: Data) -> Bool {
        XMLParser(data: data).parse()
    }

    private func idFromOPF(_ files: [EPUBFile]) -> String {
        let opf = String(decoding: files.first { $0.path == "OEBPS/content.opf" }!.data, as: UTF8.self)
        guard let r = opf.range(of: "<dc:identifier id=\"bookid\">"),
              let end = opf.range(of: "</dc:identifier>") else { return "" }
        return String(opf[r.upperBound..<end.lowerBound])
    }
}
