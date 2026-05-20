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
            "`unsupportedFormatView` must remain defined in ReaderContainerView.swift. Bug #246 removed the only caller (the `if let BookFormat(rawValue: book.format.lowercased())` guard) by routing the dispatch off `fingerprint.format` directly, but the helper is retained for future surfaces — deleting it should be a deliberate follow-up commit, not a side effect of an unrelated change."
        )
    }

    // MARK: - Source-level guard: dispatch reads canonical fingerprint format

    /// Bug #246 / GH #1072: `engineReaderView` accepts a `fingerprint`
    /// parameter parsed from `book.fingerprintKey` — which is structurally
    /// `"{format}:{sha}:{bytes}"`, so `fingerprint.format` is the authoritative
    /// canonical format for this book. The dispatch must read that field,
    /// NOT the parallel `book.format` String (a derived `@Model` field that
    /// is only set at `Book.init` from `fingerprint.format.rawValue` and is
    /// never resynced — so a SwiftData migration / direct-write / restore
    /// drift can leave `book.format` stale while `book.fingerprintKey`
    /// stays canonical). The fingerprint's already been parsed by `body`'s
    /// `DocumentFingerprint(canonicalKey:)` guard at the call site, so the
    /// only way to introduce drift is to ignore the parameter and re-derive
    /// from `book.format`.
    @Test func engineDispatchReadsCanonicalFingerprintFormat() throws {
        let source = try Self.loadSource("vreader/Views/Reader/ReaderContainerView.swift")
        guard let entry = source.range(of: "func engineReaderView") else {
            Issue.record("`engineReaderView` declaration not found")
            return
        }
        // Inspect the body of `engineReaderView` from its declaration to the
        // start of the NEXT sibling declaration. Codex Gate-4 round-2 fix:
        // an earlier version used a fixed `prefix(1500)` slice and missed
        // bytes when the function grew past that bound — a regression in
        // the function tail would slip through. Round-3 fix: anchor the
        // bound markers to top-level declaration forms (leading newline +
        // indentation) so an inline comment or string mentioning the
        // sibling name inside `engineReaderView` cannot accidentally cut
        // the bound short.
        let afterDecl = source[entry.upperBound...]
        let cutMarkers = [
            "\n    // MARK: - Error / Unsupported Views",
            "\n    var fingerprintErrorView",
            "\n    func unsupportedFormatView"
        ]
        var cutIndex: String.Index? = nil
        for marker in cutMarkers {
            if let r = afterDecl.range(of: marker) {
                if cutIndex == nil || r.lowerBound < cutIndex! { cutIndex = r.lowerBound }
            }
        }
        guard let endIndex = cutIndex else {
            Issue.record("Could not bound `engineReaderView`'s body — none of the expected sibling-declaration anchors found (looked for indented `// MARK: - Error / Unsupported Views`, `var fingerprintErrorView`, `func unsupportedFormatView`). If the file's layout changed, update the anchors above.")
            return
        }
        let bodyText = String(afterDecl[..<endIndex])
        // Positive: the dispatch must explicitly call
        // `ReaderEngine.resolve(format: fingerprint.format)` — pinning the
        // exact dispatch expression (Codex Gate-4 round-1 fix; per-substring
        // checks were too loose to catch an equivalent reintroduction via
        // a helper / temporary / different normalization).
        #expect(
            bodyText.contains("ReaderEngine.resolve(format: fingerprint.format)"),
            "Bug #246: `engineReaderView` must dispatch via `ReaderEngine.resolve(format: fingerprint.format)` — the `fingerprint` parameter (parsed once from the canonical key) is the single source of truth for routing. Reading any derived String column would re-introduce the drift class the canonical-key dispatch was added to prevent."
        )
        // Negative: NO read of `book.format` in this function — not via
        // `.lowercased()`, not via a local copy, not as `book.format` bare.
        // Drift between `book.format` (a derived `@Model` column) and
        // `book.fingerprintKey` (the canonical structural key) is the
        // precise failure mode the canonical-key dispatch eliminates;
        // banning the column read in the dispatch body keeps the bar high
        // against partial regressions that route through a temporary.
        #expect(
            !bodyText.contains("book.format"),
            "Bug #246: `engineReaderView` must NOT read `book.format` for the dispatch decision — `fingerprint.format` is already a typed `BookFormat`, and routing off the derived String column re-opens the drift class (stale column survives a SwiftData migration / restore / direct-write that leaves the canonical `fingerprintKey` correct)."
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
            // Feature #56 WI-11: the `.foliateWeb` dispatch now wraps
            // `FoliateSpikeView` inside `FoliateBilingualContainerView`
            // so the bilingual VM / orchestrator / setup-sheet wiring
            // applies without modifying the spike itself.
            ("case .foliateWeb:",    "FoliateBilingualContainerView(")
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
