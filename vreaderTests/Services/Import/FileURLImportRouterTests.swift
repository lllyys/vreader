// Purpose: Tests for FileURLImportRouter (Feature #59 WI-2).
// Covers the dispatch routing decisions — file vs. non-file URL,
// supported vs. unsupported extension, async import scheduling.
//
// The router's actual import work is asynchronous (it kicks off a Task).
// Tests assert routing-decision side effects (importer called, reporter
// called, or both bypassed) rather than the import result, which is
// exercised by BookImporter's own tests.

import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("Feature #59 — FileURLImportRouter dispatch")
struct FileURLImportRouterTests {

    // MARK: - Helpers

    /// Captured calls to the unknown-extension reporter, in order.
    final class ExtensionReporterSpy: @unchecked Sendable {
        private let lock = NSLock()
        private var _calls: [String] = []
        var calls: [String] {
            lock.lock(); defer { lock.unlock() }
            return _calls
        }
        func record(_ ext: String) {
            lock.lock(); defer { lock.unlock() }
            _calls.append(ext)
        }
    }

    private func makeRouter(spy: ExtensionReporterSpy = ExtensionReporterSpy()) -> (FileURLImportRouter, MockBookImporter, ExtensionReporterSpy) {
        let importer = MockBookImporter()
        let router = FileURLImportRouter(
            bookImporter: importer,
            reportUnknownExtension: { ext in spy.record(ext) }
        )
        return (router, importer, spy)
    }

    /// Builds a `file://` URL with the given extension. Uses /tmp/<uuid>.<ext>
    /// so the URL is well-formed even though no file actually exists at the path.
    private func fileURL(extension ext: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(UUID().uuidString).\(ext)")
    }

    // MARK: - Non-file URL rejection

    @Test("Non-file URL → router returns false, importer not called, reporter not called")
    func dispatch_nonFileURL_returnsFalse() async {
        let (router, importer, spy) = makeRouter()
        let url = URL(string: "https://example.com/book.epub")!

        let consumed = router.dispatch(url)

        #expect(consumed == false)
        #expect(spy.calls.isEmpty)
        let urls = await importer.importedURLs
        #expect(urls.isEmpty)
    }

    @Test("vreader-debug:// URL → router returns false (debug bridge handled upstream)")
    func dispatch_debugSchemeURL_returnsFalse() async {
        let (router, importer, spy) = makeRouter()
        let url = URL(string: "vreader-debug://seed?fixture=test")!

        let consumed = router.dispatch(url)

        #expect(consumed == false)
        #expect(spy.calls.isEmpty)
        let urls = await importer.importedURLs
        #expect(urls.isEmpty)
    }

    // MARK: - Supported extensions → import dispatched

    @Test(arguments: ["epub", "pdf", "txt", "text", "md", "markdown", "azw3", "azw", "mobi", "prc"])
    func dispatch_supportedExtension_callsImporter(extension ext: String) async throws {
        let (router, importer, spy) = makeRouter()
        let url = fileURL(extension: ext)

        let consumed = router.dispatch(url)

        #expect(consumed == true, "Router should consume a supported \(ext) URL")
        #expect(spy.calls.isEmpty, "Reporter must not be called for a supported extension")

        // Wait for the async Task scheduled by the router to record the import.
        // Up to ~1s polling; the MockBookImporter is in-memory so this is fast.
        for _ in 0..<50 {
            let urls = await importer.importedURLs
            if urls.contains(url) { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let urls = await importer.importedURLs
        #expect(urls.contains(url), "MockBookImporter should have received the \(ext) URL")
        let sources = await importer.importedSources
        #expect(sources.contains(.shareSheet), "Router must tag imports with .shareSheet source")
    }

    @Test("Case-insensitive supported extension → calls importer")
    func dispatch_uppercaseExtension_callsImporter() async throws {
        let (router, importer, spy) = makeRouter()
        let url = URL(fileURLWithPath: "/tmp/\(UUID().uuidString).EPUB")

        let consumed = router.dispatch(url)

        #expect(consumed == true)
        #expect(spy.calls.isEmpty)

        for _ in 0..<50 {
            let urls = await importer.importedURLs
            if urls.contains(url) { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let urls = await importer.importedURLs
        #expect(urls.contains(url))
    }

    // MARK: - Unsupported extensions → reporter called, no import

    @Test(arguments: ["zip", "docx", "rtf", "html", "xml", "json"])
    func dispatch_unsupportedExtension_callsReporter(extension ext: String) async {
        let (router, importer, spy) = makeRouter()
        let url = fileURL(extension: ext)

        let consumed = router.dispatch(url)

        #expect(consumed == true, "Router consumes unsupported-extension URLs (they were reported, not ignored)")
        #expect(spy.calls.contains(ext), "Reporter must record the unsupported extension '\(ext)'")
        let urls = await importer.importedURLs
        #expect(urls.isEmpty, "Importer must not be called for unsupported \(ext)")
    }

    @Test("File URL with no extension → reports empty extension, no import")
    func dispatch_noExtension_callsReporter() async {
        let (router, importer, spy) = makeRouter()
        let url = URL(fileURLWithPath: "/tmp/\(UUID().uuidString)")

        let consumed = router.dispatch(url)

        #expect(consumed == true)
        #expect(spy.calls.contains(""))
        let urls = await importer.importedURLs
        #expect(urls.isEmpty)
    }

    // MARK: - Importer errors are swallowed (router logs only)

    @Test("Importer throws → router does not crash; the @discardableResult still reports consumed")
    func dispatch_importerThrows_swallowsError() async throws {
        let (router, importer, spy) = makeRouter()
        await importer.setDefaultError(NSError(domain: "Test", code: 1))
        let url = fileURL(extension: "epub")

        let consumed = router.dispatch(url)
        #expect(consumed == true)
        #expect(spy.calls.isEmpty, "Importer errors are NOT reported via reportUnknownExtension")

        // Give the async Task time to attempt the import and log the error.
        for _ in 0..<50 {
            let urls = await importer.importedURLs
            if urls.contains(url) { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        let urls = await importer.importedURLs
        #expect(urls.contains(url), "Importer was called (it threw, but the call was made)")
    }
}
