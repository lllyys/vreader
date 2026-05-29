// Purpose: Feature #42 WI-11b — pin the `ReadiumBilingualCommander` eval-channel
// seam (the host-owned object the coordinator binds on attach / clears on
// detach). The commander drives the bilingual enumerate→inject→clear loop
// through Readium's one-way `evaluateJavaScript(_:) async -> Result<Any,Error>`
// channel — NOT a script-message handler (Readium owns its content controller).
//
// These tests exercise the commander through an injected evaluator stub
// (mirroring the coordinator's DEBUG `evaluatorForTests` seam) so the parse /
// dispatch contract is unit-testable without a rendered Readium spine. The
// live navigator drive itself is device slice-verified.
//
// Also pins the href-consistency normalization (seam #3 / the WI-8 finding
// class): the Readium host produces a vreader `Locator` whose href is Readium's
// CONTAINER-relative reading-order href (e.g. `OEBPS/chapter1.xhtml`), while the
// `EPUBChapterTextProvider` is keyed on vreader's OPF-relative spine hrefs
// (e.g. `chapter1.xhtml`). Without normalization `unit(containing:)` returns nil
// and NOTHING translates. The commander normalizes at the boundary via the
// shared `ReadiumDecorationHighlightAdapter.resolveHref` tolerance.
//
// @coordinates-with: ReadiumBilingualCommander.swift,
//   ReadiumBilingualEvalAdapter.swift, EPUBBilingualPipeline.swift,
//   ReadiumDecorationHighlightAdapter.swift

#if canImport(UIKit)
import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("Feature #42 WI-11b — ReadiumBilingualCommander")
struct ReadiumBilingualCommanderTests {

    // MARK: - enumerate

    @Test("enumerate parses a .success([{bid,text}]) eval result into [BilingualBlock]")
    func enumerateParsesSuccessArray() async {
        let commander = ReadiumBilingualCommander()
        commander.setEvaluator { _ in
            .success([
                ["bid": "b1", "text": "Hello"],
                ["bid": "b2", "text": "World"]
            ])
        }
        let blocks = await commander.enumerate()
        #expect(blocks == [
            BilingualBlock(bid: "b1", text: "Hello"),
            BilingualBlock(bid: "b2", text: "World")
        ])
    }

    @Test("enumerate runs the adapter's return-value enumerate JS, not a message-handler post")
    func enumerateRunsReturnValueJS() async {
        let commander = ReadiumBilingualCommander()
        nonisolated(unsafe) var seenScript: String?
        commander.setEvaluator { script in
            seenScript = script
            return .success([[String: Any]]())
        }
        _ = await commander.enumerate()
        #expect(seenScript?.contains("return out") == true)
        #expect(seenScript?.contains("webkit.messageHandlers") == false)
    }

    @Test("enumerate returns [] on a .failure eval result")
    func enumerateFailureYieldsEmpty() async {
        let commander = ReadiumBilingualCommander()
        commander.setEvaluator { _ in .failure(TestEvalError.boom) }
        let blocks = await commander.enumerate()
        #expect(blocks.isEmpty)
    }

    @Test("enumerate returns [] when no evaluator is bound (no navigator / after detach)")
    func enumerateUnboundYieldsEmpty() async {
        let commander = ReadiumBilingualCommander()
        // never setEvaluator → unbound
        let blocks = await commander.enumerate()
        #expect(blocks.isEmpty)
    }

    @Test("enumerate returns [] after clearEvaluator (late call after teardown no-ops)")
    func enumerateAfterClearYieldsEmpty() async {
        let commander = ReadiumBilingualCommander()
        commander.setEvaluator { _ in .success([["bid": "b1", "text": "x"]]) }
        commander.clearEvaluator()
        let blocks = await commander.enumerate()
        #expect(blocks.isEmpty)
    }

    // MARK: - inject

    @Test("inject feeds the adapter's inject JS (escaped) to the evaluator")
    func injectFeedsInjectJS() async {
        let commander = ReadiumBilingualCommander()
        nonisolated(unsafe) var seenScript: String?
        commander.setEvaluator { script in
            seenScript = script
            return .success(NSNull())
        }
        await commander.inject(["b1": "译文"])
        #expect(seenScript?.contains("data-vreader-decoration") == true)
        #expect(seenScript?.contains("译文") == true)
    }

    @Test("inject escapes a single-quote payload before it reaches the evaluator")
    func injectEscapesPayload() async {
        let commander = ReadiumBilingualCommander()
        nonisolated(unsafe) var seenScript: String?
        commander.setEvaluator { script in
            seenScript = script
            return .success(NSNull())
        }
        await commander.inject(["b1": "it's"])
        #expect(seenScript?.contains("it\\'s") == true)
    }

    @Test("inject no-ops (does not call evaluator) when unbound")
    func injectUnboundNoops() async {
        let commander = ReadiumBilingualCommander()
        // No evaluator. Must not crash; nothing to assert beyond no-throw.
        await commander.inject(["b1": "x"])
    }

    // MARK: - clear

    @Test("clear feeds the adapter's clear JS to the evaluator")
    func clearFeedsClearJS() async {
        let commander = ReadiumBilingualCommander()
        nonisolated(unsafe) var seenScript: String?
        commander.setEvaluator { script in
            seenScript = script
            return .success(NSNull())
        }
        await commander.clear()
        #expect(seenScript?.contains("vreader-bilingual") == true)
        #expect(seenScript?.contains("removeChild") == true)
    }

    // MARK: - href-consistency normalization (seam #3)

    @Test("a Readium container-relative locator href resolves to the provider's OPF spine unit")
    func readiumHrefNormalizesToOPFSpine() {
        // The provider's OPF-relative spine hrefs (vreader EPUBParser convention).
        let opfSpine = ["chapter1.xhtml", "chapter2.xhtml"]
        // A vreader Locator built by the Readium host carries Readium's
        // container-relative reading-order href.
        let fp = DocumentFingerprint(
            contentSHA256: String(repeating: "a", count: 64),
            fileByteCount: 10, format: .epub)
        let readiumStyle = Locator(
            bookFingerprint: fp, href: "OEBPS/chapter2.xhtml",
            progression: 0.5, totalProgression: nil, cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil)
        let normalized = ReadiumBilingualCommander.normalizedLocator(
            readiumStyle, toSpineHrefs: opfSpine)
        #expect(normalized.href == "chapter2.xhtml")
        // progression + fingerprint preserved so the prefetch trigger is intact.
        #expect(normalized.progression == 0.5)
    }

    @Test("an already-OPF-form locator href passes through unchanged")
    func opfHrefPassesThrough() {
        let opfSpine = ["chapter1.xhtml"]
        let fp = DocumentFingerprint(
            contentSHA256: String(repeating: "b", count: 64),
            fileByteCount: 10, format: .epub)
        let already = Locator(
            bookFingerprint: fp, href: "chapter1.xhtml",
            progression: 0.1, totalProgression: nil, cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil)
        let normalized = ReadiumBilingualCommander.normalizedLocator(
            already, toSpineHrefs: opfSpine)
        #expect(normalized.href == "chapter1.xhtml")
    }

    @Test("an unresolvable href is left raw (no safe match → keep stored, never drop)")
    func unresolvableHrefLeftRaw() {
        let opfSpine = ["chapter1.xhtml", "chapter2.xhtml"]
        let fp = DocumentFingerprint(
            contentSHA256: String(repeating: "c", count: 64),
            fileByteCount: 10, format: .epub)
        let mystery = Locator(
            bookFingerprint: fp, href: "totally/unknown.xhtml",
            progression: nil, totalProgression: nil, cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil)
        let normalized = ReadiumBilingualCommander.normalizedLocator(
            mystery, toSpineHrefs: opfSpine)
        #expect(normalized.href == "totally/unknown.xhtml")
    }
}

private enum TestEvalError: Error { case boom }
#endif
