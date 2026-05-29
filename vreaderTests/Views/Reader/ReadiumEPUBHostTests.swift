// Purpose: Feature #42 Phase 1 WI-5 — unit tests for the testable seams of the
// Readium EPUB host: (1) the pure dispatch routing decision (flag ON →
// `.epubReadium`, flag OFF → `.epubWKWebView`); (2) the `EPUBLayoutPreference`
// → Readium `EPUBPreferences(scroll:)` mapping; (3) the coordinator's
// `ReadiumNavigatorEvaluating` JSON serialization of a navigator eval result
// (fed through a stub navigator-evaluator closure so no real WebView renders).
//
// The render itself (UIViewControllerRepresentable hosting
// EPUBNavigatorViewController) is exercised by device verification, not here.
//
// @coordinates-with vreader/Views/Reader/ReadiumEPUBHost.swift,
//   vreader/ViewModels/ReadiumEPUBReaderViewModel.swift,
//   vreader/Models/ReaderEngine.swift

import Testing
import Foundation
import ReadiumNavigator
@testable import vreader

@Suite("ReadiumEPUBHost (WI-5)")
struct ReadiumEPUBHostTests {

    // MARK: - Dispatch routing (pure, flag-driven)

    @Test func routeEPUB_flagOff_isLegacyWKWebView() {
        #expect(ReaderEngine.routeEPUB(readiumFlagEnabled: false) == .epubWKWebView)
    }

    @Test func routeEPUB_flagOn_isReadium() {
        #expect(ReaderEngine.routeEPUB(readiumFlagEnabled: true) == .epubReadium)
    }

    /// `resolve(format:)` stays the pure format→default-engine map (the flag
    /// branch lives in the dispatcher, NOT here) — EPUB still resolves to the
    /// legacy engine so a flag-unaware caller gets today's behavior.
    @Test func resolve_epub_unchanged_isLegacy() {
        #expect(ReaderEngine.resolve(format: .epub) == .epubWKWebView)
    }

    @Test func epubReadium_isACase_andRoundTrips() {
        #expect(ReaderEngine.allCases.contains(.epubReadium))
        #expect(ReaderEngine(rawValue: "epubReadium") == .epubReadium)
        #expect(ReaderEngine.epubReadium.rawValue == "epubReadium")
    }

    // MARK: - EPUBLayoutPreference → EPUBPreferences(scroll:)

    @Test func preferences_scrollLayout_enablesScroll() {
        let prefs = ReadiumEPUBReaderViewModel.epubPreferences(for: .scroll)
        #expect(prefs.scroll == true)
    }

    @Test func preferences_pagedLayout_disablesScroll() {
        let prefs = ReadiumEPUBReaderViewModel.epubPreferences(for: .paged)
        #expect(prefs.scroll == false)
    }

    // MARK: - Coordinator eval serialization (ReadiumNavigatorEvaluating)

    /// Stub navigator-evaluator that returns a caller-supplied raw value (the
    /// shape Readium's `evaluateJavaScript(_:) -> Result<Any, Error>` yields on
    /// success), so the coordinator's JSON-serialization contract is testable
    /// without a real spine WebView.
    @MainActor
    private func coordinator(returning value: Any?) -> ReadiumReaderCoordinator {
        let coord = ReadiumReaderCoordinator(
            fingerprintKey: "epub:\(String(repeating: "a", count: 64)):10",
            readerToken: UUID()
        )
        coord.evaluatorForTests = { _ in value }
        return coord
    }

    @MainActor
    private func decode(_ data: Data) throws -> Any {
        try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    @MainActor @Test func eval_serializesNumber() async throws {
        let data = try await coordinator(returning: 42).evaluateJavaScriptValue("1+41")
        #expect(try decode(data) as? Int == 42)
    }

    @MainActor @Test func eval_serializesString() async throws {
        let data = try await coordinator(returning: "hello").evaluateJavaScriptValue("'hello'")
        #expect(try decode(data) as? String == "hello")
    }

    @MainActor @Test func eval_serializesArray() async throws {
        let data = try await coordinator(returning: [1, 2, 3]).evaluateJavaScriptValue("[1,2,3]")
        let arr = try decode(data) as? [Int]
        #expect(arr == [1, 2, 3])
    }

    @MainActor @Test func eval_serializesObject() async throws {
        let data = try await coordinator(returning: ["k": "v"]).evaluateJavaScriptValue("({k:'v'})")
        let obj = try decode(data) as? [String: String]
        #expect(obj?["k"] == "v")
    }

    /// JS `undefined` / Swift `nil` → JSON `null` (mirrors the EPUB/Foliate
    /// jsEvaluator `raw ?? NSNull()` contract so the bridge can splat it).
    @MainActor @Test func eval_undefinedBecomesNull() async throws {
        let data = try await coordinator(returning: nil).evaluateJavaScriptValue("void 0")
        #expect(try decode(data) is NSNull)
    }

    /// CJK string round-trips through UTF-8 JSON without mojibake (edge case).
    @MainActor @Test func eval_serializesCJK() async throws {
        let data = try await coordinator(returning: "被讨厌的勇气").evaluateJavaScriptValue("title")
        #expect(try decode(data) as? String == "被讨厌的勇气")
    }
}
