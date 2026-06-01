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
    func mimetypeFirstStored() {
        let files = MobiEPUBAssembler.assemble(parts: sampleParts, title: "T")
        #expect(files.first?.path == "mimetype")
        #expect(files.first?.isStored == true)
        #expect(String(decoding: files[0].data, as: UTF8.self) == "application/epub+zip")
        #expect(files.dropFirst().allSatisfy { !$0.isStored })
    }

    @Test("container.xml points at OEBPS/content.opf and is well-formed XML")
    func containerXMLValid() throws {
        let files = MobiEPUBAssembler.assemble(parts: sampleParts, title: "T")
        let container = try #require(files.first { $0.path == "META-INF/container.xml" })
        let s = String(decoding: container.data, as: UTF8.self)
        #expect(s.contains("full-path=\"OEBPS/content.opf\""))
        #expect(isWellFormedXML(container.data))
    }

    @Test("content.opf manifests every part + nav, spine is markup in decode order")
    func opfManifestAndSpine() throws {
        let files = MobiEPUBAssembler.assemble(parts: sampleParts, title: "T")
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
        let files = MobiEPUBAssembler.assemble(parts: sampleParts, title: "T")
        let p0 = try #require(files.first { $0.path == "OEBPS/text/part0000.xhtml" })
        #expect(String(decoding: p0.data, as: UTF8.self).contains("Chapter 1"))
        let css = try #require(files.first { $0.path == "OEBPS/styles/flow0000.css" })
        #expect(String(decoding: css.data, as: UTF8.self).contains("margin"))
        #expect(files.contains { $0.path == "OEBPS/resources/res0000.jpg" })
        #expect(files.contains { $0.path == "OEBPS/nav.xhtml" })
    }

    @Test("title is XML-escaped in the opf")
    func titleEscaped() {
        let files = MobiEPUBAssembler.assemble(parts: sampleParts, title: "A & B <c>")
        let opf = String(decoding: files.first { $0.path == "OEBPS/content.opf" }!.data, as: UTF8.self)
        #expect(opf.contains("A &amp; B &lt;c&gt;"))
        #expect(!opf.contains("<dc:title>A & B <c></dc:title>"))
        #expect(isWellFormedXML(files.first { $0.path == "OEBPS/content.opf" }!.data))
    }

    @Test("assembly is deterministic — same parts yield byte-identical output")
    func deterministic() {
        #expect(MobiEPUBAssembler.assemble(parts: sampleParts, title: "T")
                == MobiEPUBAssembler.assemble(parts: sampleParts, title: "T"))
    }

    @Test("package identifier is content-addressed — different content → different id")
    func contentAddressedID() {
        let a = idFromOPF(MobiEPUBAssembler.assemble(parts: sampleParts, title: "T"))
        var other = sampleParts
        other[0] = part(.markup, 0, "html", "<html><body>different content entirely</body></html>")
        let b = idFromOPF(MobiEPUBAssembler.assemble(parts: other, title: "T"))
        #expect(!a.isEmpty && !b.isEmpty)
        #expect(a != b)
    }

    @Test("no markup → empty spine, but still a valid package")
    func noMarkup() throws {
        let resourceOnly = [part(.resource, 0, "png", "img")]
        let files = MobiEPUBAssembler.assemble(parts: resourceOnly, title: "T")
        let opf = try #require(files.first { $0.path == "OEBPS/content.opf" })
        #expect(isWellFormedXML(opf.data))
        #expect(String(decoding: opf.data, as: UTF8.self).contains("<spine>"))
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
