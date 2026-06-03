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

    // MARK: - Gate-4 round-3 MED-2: failure (nil) vs success-empty ([]) contract.
    // enumerate() returns `[BilingualBlock]?`: `nil` = eval FAILURE / unbound /
    // detached (a transient that the driver must be free to RETRY); `[]` =
    // a successful eval over a chapter with no translatable blocks (the driver
    // COMMITS so it does not retry-loop forever on a genuinely-empty chapter).

    @Test("enumerate returns a successful EMPTY array (not nil) for a chapter with no blocks")
    func enumerateSuccessEmptyIsNonNil() async {
        let commander = ReadiumBilingualCommander()
        commander.setEvaluator { _ in .success([[String: Any]]()) }
        let blocks = await commander.enumerate()
        // A real array that parses to zero blocks is success-empty, NOT a failure.
        #expect(blocks != nil)
        #expect(blocks?.isEmpty == true)
    }

    @Test("enumerate returns a successful EMPTY {blocks:[]} envelope (not nil)")
    func enumerateSuccessEmptyEnvelopeIsNonNil() async {
        let commander = ReadiumBilingualCommander()
        commander.setEvaluator { _ in .success(["blocks": [[String: Any]]()]) }
        let blocks = await commander.enumerate()
        // A valid envelope whose `blocks` array is empty is success-empty, NOT a
        // failure — the driver must COMMIT (no retry-loop on a real empty chapter).
        #expect(blocks != nil)
        #expect(blocks?.isEmpty == true)
    }

    // Gate-4 round-3 MED (Finding A): a MALFORMED `.success` payload (the eval
    // returned garbage — a string, a number, or a dict with no `blocks` array) is
    // a real PARSE FAILURE, not success-empty. `parseEnumerateMessage` tolerantly
    // returns `[]` for garbage, so `enumerate()` must gate on a POSITIVE shape
    // check (bare `[Any]` array OR `[String:Any]` envelope with a `blocks` array)
    // and return `nil` otherwise — else the driver commits `lastEnumeratedHref`
    // and the chapter is permanently deduped, never retried after a bad payload.

    @Test("enumerate returns nil (PARSE FAILURE) for a malformed bare-string .success payload")
    func enumerateMalformedStringYieldsNil() async {
        let commander = ReadiumBilingualCommander()
        commander.setEvaluator { _ in .success("oops") }
        let blocks = await commander.enumerate()
        #expect(blocks == nil)
    }

    @Test("enumerate returns nil (PARSE FAILURE) for a malformed numeric .success payload")
    func enumerateMalformedNumberYieldsNil() async {
        let commander = ReadiumBilingualCommander()
        commander.setEvaluator { _ in .success(42) }
        let blocks = await commander.enumerate()
        #expect(blocks == nil)
    }

    @Test("enumerate returns nil (PARSE FAILURE) for a dict with no `blocks` array")
    func enumerateMalformedDictNoBlocksYieldsNil() async {
        let commander = ReadiumBilingualCommander()
        commander.setEvaluator { _ in .success(["error": "boom"]) }
        let blocks = await commander.enumerate()
        #expect(blocks == nil)
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

    @Test("enumerate returns nil (FAILURE, retryable) on a .failure eval result")
    func enumerateFailureYieldsNil() async {
        let commander = ReadiumBilingualCommander()
        commander.setEvaluator { _ in .failure(TestEvalError.boom) }
        let blocks = await commander.enumerate()
        #expect(blocks == nil)
    }

    @Test("enumerate returns nil (FAILURE) when no evaluator is bound (no navigator / after detach)")
    func enumerateUnboundYieldsNil() async {
        let commander = ReadiumBilingualCommander()
        // never setEvaluator → unbound → not a success, must be retryable
        let blocks = await commander.enumerate()
        #expect(blocks == nil)
    }

    @Test("enumerate returns nil (FAILURE) after clearEvaluator (late call after teardown no-ops)")
    func enumerateAfterClearYieldsNil() async {
        let commander = ReadiumBilingualCommander()
        commander.setEvaluator { _ in .success([["bid": "b1", "text": "x"]]) }
        commander.clearEvaluator()
        let blocks = await commander.enumerate()
        #expect(blocks == nil)
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

    // MARK: - loading shimmer (Feature #77 WI-2)

    @Test("injectLoading feeds the adapter's loading JS to the evaluator")
    func injectLoadingFeedsLoadingJS() async {
        let commander = ReadiumBilingualCommander()
        nonisolated(unsafe) var seenScript: String?
        commander.setEvaluator { script in
            seenScript = script
            return .success(NSNull())
        }
        await commander.injectLoading(["b1", "b2"])
        #expect(seenScript?.contains(EPUBBilingualJS.loadingClassName) == true)
        #expect(seenScript?.contains(EPUBBilingualJS.shimmerBarClassName) == true)
        #expect(seenScript?.contains("'b1'") == true)
    }

    @Test("injectLoading no-ops (does not call evaluator) when bids is empty")
    func injectLoadingEmptyNoops() async {
        let commander = ReadiumBilingualCommander()
        nonisolated(unsafe) var called = false
        commander.setEvaluator { _ in called = true; return .success(NSNull()) }
        await commander.injectLoading([])
        #expect(called == false)
    }

    @Test("injectLoading no-ops when unbound (no navigator / after detach)")
    func injectLoadingUnboundNoops() async {
        let commander = ReadiumBilingualCommander()
        await commander.injectLoading(["b1"])   // must not crash
    }

    @Test("clearLoading feeds the loading-only clear JS to the evaluator")
    func clearLoadingFeedsClearLoadingJS() async {
        let commander = ReadiumBilingualCommander()
        nonisolated(unsafe) var seenScript: String?
        commander.setEvaluator { script in
            seenScript = script
            return .success(NSNull())
        }
        await commander.clearLoading()
        #expect(seenScript?.contains(EPUBBilingualJS.loadingClassName) == true)
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

    @Test("LOW-7: an ambiguous basename (matches >1 spine entry) is left raw, never mis-resolved")
    func ambiguousBasenameLeftRaw() {
        // Two spine entries share the same basename `chapter.xhtml` under
        // different directories. A Readium href whose basename matches both is
        // ambiguous — `resolveHref` returns nil (suffix `/chapter.xhtml` matches
        // both), so normalization keeps the RAW href rather than guessing the
        // wrong chapter (which would translate the wrong unit).
        let opfSpine = ["part1/chapter.xhtml", "part2/chapter.xhtml"]
        let fp = DocumentFingerprint(
            contentSHA256: String(repeating: "d", count: 64),
            fileByteCount: 10, format: .epub)
        let ambiguous = Locator(
            bookFingerprint: fp, href: "chapter.xhtml",
            progression: 0.3, totalProgression: nil, cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil)
        let normalized = ReadiumBilingualCommander.normalizedLocator(
            ambiguous, toSpineHrefs: opfSpine)
        #expect(normalized.href == "chapter.xhtml")
        #expect(normalized.progression == 0.3)
    }
}

private enum TestEvalError: Error { case boom }
#endif
