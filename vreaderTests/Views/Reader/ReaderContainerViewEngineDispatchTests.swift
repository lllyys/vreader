// Purpose: Regression guard for feature #54 WI-3 — ReaderContainerView routes
// to format hosts by `ReaderEngine`, not by the retired `ReadingMode` toggle.
//
// WI-3 collapses the `readingMode == .unified` dispatch branch: `body` calls
// `engineReaderView(fingerprint:)` unconditionally, and that method switches on
// `ReaderEngine.resolve(format:)` instead of a stringly-typed `book.format`
// switch. The unified-mode dispatch (`ReaderUnifiedDispatch.swift`,
// `UnifiedPlaceholderView.swift`) is deleted.
//
// These tests pin (a) the engine-routing invariant — each BookFormat maps to
// the host its engine implies — and (b) source-level guards that the
// `readingMode`-based dispatch and the unified-mode files are gone.
//
// @coordinates-with: vreader/Views/Reader/ReaderContainerView.swift,
//   vreader/Models/ReaderEngine.swift

import Testing
import Foundation
@testable import vreader

@Suite("ReaderContainerView engine dispatch (feature #54 WI-3)")
struct ReaderContainerViewEngineDispatchTests {

    // MARK: - Source loading

    /// Loads a production source file by walking up from this test's
    /// compile-time `#filePath` to the repo root. `#filePath` is a literal
    /// baked in at compile time — reliable where `SRCROOT` is not.
    private static func loadSource(
        _ relativePath: String,
        testFilePath: String = #filePath
    ) throws -> String {
        let repoRoot = URL(fileURLWithPath: testFilePath)
            .deletingLastPathComponent() // Reader/
            .deletingLastPathComponent() // Views/
            .deletingLastPathComponent() // vreaderTests/
            .deletingLastPathComponent() // repo root
        return try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    /// Whether a file exists relative to the repo root.
    private static func fileExists(
        _ relativePath: String,
        testFilePath: String = #filePath
    ) -> Bool {
        let repoRoot = URL(fileURLWithPath: testFilePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return FileManager.default.fileExists(
            atPath: repoRoot.appendingPathComponent(relativePath).path
        )
    }

    // MARK: - Engine routing invariant

    /// The five hosts the dispatcher routes to, keyed by engine. Each
    /// BookFormat resolves to exactly one engine, and that engine determines
    /// the host — this is the contract `engineReaderView` must honor.
    @Test func everyBookFormatResolvesToItsExpectedEngine() {
        let expected: [BookFormat: ReaderEngine] = [
            .txt:  .textNative,
            .md:   .markdownNative,
            .epub: .epubWKWebView,
            .azw3: .foliateWeb,
            .pdf:  .pdfKit
        ]
        for format in BookFormat.allCases {
            #expect(
                ReaderEngine.resolve(format: format) == expected[format],
                "BookFormat.\(format.rawValue) must resolve to \(String(describing: expected[format]))"
            )
        }
    }

    /// `ReaderEngine` covers every host the dispatcher needs — no BookFormat
    /// falls through to an unhandled engine.
    @Test func engineResolutionIsTotalOverBookFormat() {
        for format in BookFormat.allCases {
            let engine = ReaderEngine.resolve(format: format)
            #expect(ReaderEngine.allCases.contains(engine))
        }
    }

    // MARK: - Source-level guards: dispatch no longer reads readingMode

    @Test func dispatchDoesNotBranchOnReadingMode() throws {
        let source = try Self.loadSource("vreader/Views/Reader/ReaderContainerView.swift")
        // The retired branch condition. After WI-3 the dispatch is
        // unconditional — no `readingMode == .unified` test in the routing
        // path.
        #expect(
            !source.contains("readingMode == .unified"),
            "ReaderContainerView must not branch the dispatch on `readingMode == .unified` — feature #54 WI-3 routes by ReaderEngine. Found a surviving reference."
        )
        #expect(
            !source.contains(".readingMode"),
            "ReaderContainerView dispatch path must not read `.readingMode` — the field is retired from the routing decision (feature #54 WI-3)."
        )
    }

    @Test func dispatchRoutesThroughReaderEngineResolve() throws {
        let source = try Self.loadSource("vreader/Views/Reader/ReaderContainerView.swift")
        #expect(
            source.contains("ReaderEngine.resolve(format:"),
            "ReaderContainerView must route through `ReaderEngine.resolve(format:)` (feature #54 WI-3)."
        )
    }

    @Test func unifiedReaderViewDispatchIsRemoved() throws {
        let source = try Self.loadSource("vreader/Views/Reader/ReaderContainerView.swift")
        #expect(
            !source.contains("unifiedReaderView"),
            "The `unifiedReaderView` dispatch is deleted by feature #54 WI-3 — `body` calls `engineReaderView` unconditionally."
        )
    }

    // MARK: - Source-level guards: unified-mode files are deleted

    @Test func readerUnifiedDispatchFileIsDeleted() {
        #expect(
            !Self.fileExists("vreader/Views/Reader/ReaderUnifiedDispatch.swift"),
            "ReaderUnifiedDispatch.swift must be deleted by feature #54 WI-3 — its `fingerprintErrorView` / `unsupportedFormatView` move into ReaderContainerView.swift; `unifiedReaderView` is removed."
        )
    }

    @Test func unifiedPlaceholderViewFileIsDeleted() {
        #expect(
            !Self.fileExists("vreader/Views/Reader/UnifiedPlaceholderView.swift"),
            "UnifiedPlaceholderView.swift must be deleted by feature #54 WI-3 — its only entry point (the unified dispatch `default:` case) is removed."
        )
    }

    // MARK: - Source-level guards: error views still exist

    @Test func fingerprintErrorViewMovedIntoContainer() throws {
        let source = try Self.loadSource("vreader/Views/Reader/ReaderContainerView.swift")
        #expect(
            source.contains("fingerprintErrorView"),
            "`fingerprintErrorView` must move into ReaderContainerView.swift — it is still referenced by the fingerprint-guard `else` branch."
        )
    }

    @Test func unsupportedFormatViewMovedIntoContainer() throws {
        let source = try Self.loadSource("vreader/Views/Reader/ReaderContainerView.swift")
        #expect(
            source.contains("unsupportedFormatView"),
            "`unsupportedFormatView` must move into ReaderContainerView.swift — `engineReaderView`'s unknown-format path still uses it."
        )
    }

    // MARK: - Source-level guard: each engine case maps to its host

    /// The engine-resolution invariant above proves `ReaderEngine.resolve`
    /// is correct, but a future mistake could keep `resolve` correct while
    /// swapping the view cases in `engineReaderView`. This guard pins the
    /// `engine case → host` wiring inside `engineReaderView` itself: each
    /// `case .<engine>:` must be followed by the host its engine implies.
    @Test func engineReaderViewMapsEachEngineCaseToItsHost() throws {
        let source = try Self.loadSource("vreader/Views/Reader/ReaderContainerView.swift")
        // (engine case, host the case must construct).
        let wiring: [(caseLabel: String, host: String)] = [
            ("case .textNative:",    "TXTReaderHost("),
            ("case .markdownNative:", "MDReaderHost("),
            ("case .epubWKWebView:", "EPUBReaderHost("),
            ("case .pdfKit:",        "PDFReaderHost("),
            ("case .foliateWeb:",    "FoliateSpikeView(")
        ]
        for (caseLabel, host) in wiring {
            guard let caseIndex = source.range(of: caseLabel) else {
                Issue.record("`engineReaderView` is missing `\(caseLabel)`")
                continue
            }
            // The host construction must appear after this case label and
            // before the next `case ` label (or the switch's close).
            let afterCase = source[caseIndex.upperBound...]
            let nextCase = afterCase.range(of: "\n            case .")
            let caseBody = nextCase.map { String(afterCase[..<$0.lowerBound]) }
                ?? String(afterCase.prefix(400))
            #expect(
                caseBody.contains(host),
                "`engineReaderView` `\(caseLabel)` must construct `\(host)` — the engine-to-host wiring."
            )
        }
    }
}
