// Purpose: Feature #68 WI-3 — tests that MDReaderViewModel.open applies
// MDChapterStartDecorator to the rendered attributed string while keeping
// renderedText byte-identical to the undecorated render (offset safety),
// and that a different renderConfig on a second open recolors the
// decoration (the "next open" theme contract — MD has no live re-theme).
//
// @coordinates-with: MDReaderViewModel.swift, MDChapterStartDecorator.swift

#if canImport(UIKit)
import Testing
import Foundation
import UIKit
@testable import vreader

@Suite("MDReaderViewModel — chapter-start (feature #68 WI-3)")
@MainActor
struct MDReaderViewModelChapterStartTests {

    private let fingerprint = DocumentFingerprint(
        contentSHA256: "md_vm_cs_test_sha256_0000000000000000000000000000000000000000",
        fileByteCount: 300,
        format: .md
    )

    private func config(accent: UIColor) -> MDRenderConfig {
        var c = MDRenderConfig.default
        c.fontSize = 18
        c.accentColor = accent
        c.chapterHeadingColor = UIColor(white: 0.4, alpha: 1.0)
        return c
    }

    /// Builds a VM whose mock parser returns the *real*
    /// `MDAttributedStringRenderer.render` output for `md`.
    private func makeVM(md: String, renderConfig: MDRenderConfig)
        -> (MDReaderViewModel, MockMDParser) {
        let parser = MockMDParser()
        parser.setDocumentInfo(
            MDAttributedStringRenderer.render(text: md, config: renderConfig)
        )
        let tracker = ReadingSessionTracker(
            clock: MockClock(), store: MockSessionStore(), deviceId: "test-device"
        )
        let vm = MDReaderViewModel(
            bookFingerprint: fingerprint,
            parser: parser,
            positionStore: MockPositionStore(),
            sessionTracker: tracker,
            deviceId: "test-device"
        )
        return (vm, parser)
    }

    private func writeTempMD(_ source: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("md_vm_cs_\(UUID().uuidString).md")
        try source.data(using: .utf8)!.write(to: url)
        return url
    }

    private func hasDropCap(_ s: NSAttributedString, fontSize: CGFloat = 18) -> Bool {
        var found = false
        s.enumerateAttribute(.font, in: NSRange(location: 0, length: s.length)) { value, _, _ in
            if let f = value as? UIFont,
               f.pointSize >= fontSize * ChapterStartTypography.dropCapScale - 0.5 {
                found = true
            }
        }
        return found
    }

    @Test("open applies the chapter-start decoration to renderedAttributedString")
    func openAppliesDecoration() async throws {
        let accent = UIColor(red: 0.55, green: 0.18, blue: 0.18, alpha: 1.0)
        let cfg = config(accent: accent)
        let (vm, _) = makeVM(md: "# Chapter One\n\nBody paragraph text here.", renderConfig: cfg)
        let url = try writeTempMD("# Chapter One\n\nBody paragraph text here.")
        defer { try? FileManager.default.removeItem(at: url) }

        await vm.open(url: url, renderConfig: cfg)

        let attr = try #require(vm.renderedAttributedString)
        #expect(hasDropCap(attr))
    }

    @Test("renderedText stays byte-identical to the undecorated render")
    func renderedTextOffsetSafety() async throws {
        let cfg = config(accent: .red)
        let md = "# Chapter One\n\nBody paragraph text here for offset safety."
        let (vm, _) = makeVM(md: md, renderConfig: cfg)
        let url = try writeTempMD(md)
        defer { try? FileManager.default.removeItem(at: url) }

        await vm.open(url: url, renderConfig: cfg)

        // The undecorated render's plain text.
        let undecorated = MDAttributedStringRenderer.render(text: md, config: cfg)
        #expect(vm.renderedText == undecorated.renderedText)
        #expect(vm.renderedTextLengthUTF16 == undecorated.renderedTextLengthUTF16)
        // The decorated attributed string's backing string is also identical.
        #expect(vm.renderedAttributedString?.string == undecorated.renderedText)
    }

    @Test("open with the default renderConfig still loads and renders (back-compat)")
    func openWithDefaultConfig() async throws {
        let md = "# Title\n\nBody text."
        let (vm, _) = makeVM(md: md, renderConfig: .default)
        let url = try writeTempMD(md)
        defer { try? FileManager.default.removeItem(at: url) }

        await vm.open(url: url)

        #expect(vm.renderedText != nil)
        #expect(vm.renderedAttributedString != nil)
    }

    @Test("reopening with a different renderConfig recolors the decoration (next-open contract)")
    func reopenWithDifferentConfigRecolors() async throws {
        // MD has no live theme re-render path — colors apply on the NEXT
        // open. This pins that contract: a second open with a different
        // accent produces decoration carrying the new color.
        let md = "# Chapter One\n\nBody paragraph text here for recolor."
        let url = try writeTempMD(md)
        defer { try? FileManager.default.removeItem(at: url) }

        let firstAccent = UIColor(red: 0.55, green: 0.18, blue: 0.18, alpha: 1.0)
        let cfg1 = config(accent: firstAccent)
        let (vm, parser) = makeVM(md: md, renderConfig: cfg1)
        await vm.open(url: url, renderConfig: cfg1)
        let firstColor = vm.renderedAttributedString?
            .attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor

        // Reopen with a different accent — re-seed the mock so the
        // re-parse produces the new-config render too.
        let secondAccent = UIColor(red: 0.84, green: 0.53, blue: 0.35, alpha: 1.0)
        let cfg2 = config(accent: secondAccent)
        parser.setDocumentInfo(
            MDAttributedStringRenderer.render(text: md, config: cfg2)
        )
        await vm.open(url: url, renderConfig: cfg2)
        let secondColor = vm.renderedAttributedString?
            .attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor

        // The heading run at offset 0 is restyled to chapterHeadingColor;
        // both opens produce that color, but the drop-cap color differs.
        // Assert the decoration as a whole changed between the two opens.
        #expect(firstColor != nil)
        #expect(secondColor != nil)
        // Find the drop-cap run and confirm it carries the active accent.
        let attr = try #require(vm.renderedAttributedString)
        var dropCapColor: UIColor?
        attr.enumerateAttribute(.font, in: NSRange(location: 0, length: attr.length)) { value, range, _ in
            if let f = value as? UIFont,
               f.pointSize >= 18 * ChapterStartTypography.dropCapScale - 0.5 {
                dropCapColor = attr.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? UIColor
            }
        }
        #expect(dropCapColor == secondAccent)
    }
}
#endif
