// Purpose: Dispatches incoming `file://` URLs from iOS Share Sheet / "Open in"
// to the BookImporter. Used by VReaderApp's production `.onOpenURL` handler
// (Feature #59 WI-2). Debug-bridge URLs (vreader-debug://) are handled
// upstream by the App's existing scheme guard and never reach this router.
//
// Design:
//   - Depends on `any BookImporting` (not concrete BookImporter) so unit
//     tests can inject a mock and assert dispatch routing without touching
//     SwiftUI Scene plumbing.
//   - `reportUnknownExtension` is injected as a closure so the unsupported-
//     extension UX (alert / toast) lives in the App layer, not bundled into
//     the router. Tests inject a captured-call array.
//   - Security-scope handling is OWNED by BookImporter (it calls
//     `startAccessingSecurityScopedResource` internally at line 85 of
//     BookImporter.swift). The router does NOT re-scope; doing so would
//     double-balance the access counter.
//
// @coordinates-with: VReaderApp.swift (onOpenURL wiring), BookImporting.swift
//   (the protocol surface), BookFormat.swift (isSupportedExtension)

import Foundation
import OSLog

@MainActor
final class FileURLImportRouter {
    private let bookImporter: any BookImporting
    private let reportUnknownExtension: (String) -> Void
    private let logger = Logger(subsystem: "com.vreader.app", category: "FileURLImportRouter")

    init(
        bookImporter: any BookImporting,
        reportUnknownExtension: @escaping (String) -> Void = { _ in }
    ) {
        self.bookImporter = bookImporter
        self.reportUnknownExtension = reportUnknownExtension
    }

    /// Dispatches an incoming URL. Returns true iff this router consumed it
    /// (either started an import or reported an unsupported extension to the
    /// user). Returns false for non-file URLs so the caller can fall through
    /// to any other handler (e.g., the Debug `vreader-debug://` scheme — but
    /// in practice the App layer routes those first, so they never reach here).
    ///
    /// Discardable because the App-layer caller may not always need the result;
    /// the router's side effects (kicking off import or surfacing the alert)
    /// are the meaningful outcomes.
    @discardableResult
    func dispatch(_ url: URL) -> Bool {
        guard url.isFileURL else {
            logger.debug("Ignoring non-file URL scheme: \(url.scheme ?? "<nil>", privacy: .public)")
            return false
        }

        let pathExtension = url.pathExtension
        guard BookFormat.isSupportedExtension(pathExtension) else {
            logger.info("Unsupported extension '\(pathExtension, privacy: .public)' for incoming file URL; reporting to user")
            reportUnknownExtension(pathExtension)
            return true
        }

        // Capture the URL by value before launching the Task — `url` is a
        // value type and Sendable, so this is safe.
        Task { @MainActor [bookImporter, logger] in
            do {
                let result = try await bookImporter.importFile(at: url, source: .shareSheet)
                logger.info("Imported \(result.title, privacy: .private(mask: .hash)) from incoming URL (duplicate=\(result.isDuplicate, privacy: .public))")
            } catch {
                // Surfacing import errors to the UI is the App-layer's job; the
                // router only logs. The user already sees the system's "Open in
                // vreader" launch state — a follow-up toast / alert would be a
                // separate iteration's polish.
                logger.error("Import failed for incoming URL: \(String(describing: error), privacy: .public)")
            }
        }
        return true
    }
}
