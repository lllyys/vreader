// Purpose: Feature #42 Phase 1 (WI-5) — @MainActor view model that opens an EPUB
// through the Readium 3.x opening flow (AssetRetriever → PublicationOpener with
// DefaultPublicationParser) off the main actor, then hands the resulting
// `Publication` back to the main actor so `ReadiumEPUBHost` can mount an
// `EPUBNavigatorViewController`. Holds the open lifecycle state (loading /
// ready / failed) the host renders, and the pure `epubPreferences(for:)`
// translation from vreader's `EPUBLayoutPreference` to Readium `EPUBPreferences`.
//
// Scope (WI-5): open + render + scroll/paginate behind the `readiumEPUBEngine`
// flag. Position save/restore (VReaderLocator ↔ Readium Locator), highlights,
// theme/font, search, and TTS land in later WIs (WI-6…WI-10). This VM stays
// thin — it owns opening and layout-preference mapping only.
//
// Concurrency (feature #42 round-1 Med-4): the open is `async` and runs off the
// main actor inside Readium's own executors; the `Publication` reference is
// handed back to this @MainActor VM. No WebKit/UIKit object is stored in a
// Sendable actor — the navigator itself is owned by the host's coordinator.
//
// @coordinates-with ReadiumEPUBHost.swift, EPUBLayoutPreference.swift

import Foundation
import OSLog
import ReadiumShared
import ReadiumStreamer
import ReadiumNavigator

@MainActor
@Observable
final class ReadiumEPUBReaderViewModel {

    /// Open lifecycle the host renders.
    enum OpenState {
        case loading
        case ready(Publication)
        case failed(String)
    }

    private(set) var state: OpenState = .loading

    private let fileURL: URL
    private let log = Logger(subsystem: "com.vreader.app", category: "ReadiumEPUB")

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    // MARK: - Opening

    /// Opens the EPUB via Readium's `AssetRetriever` → `PublicationOpener`.
    /// Idempotent: a second call after a successful open is a no-op so a
    /// transient host re-mount does not reopen. The heavy parse runs inside
    /// Readium's async executors (off the main actor); the `Publication` is
    /// stored back on this @MainActor VM.
    func open() async {
        if case .ready = state { return }

        guard let assetURL = FileURL(url: fileURL) else {
            state = .failed("invalid file URL")
            log.error("ReadiumEPUB open: invalid FileURL")
            return
        }

        let httpClient = DefaultHTTPClient()
        let assetRetriever = AssetRetriever(httpClient: httpClient)
        let opener = PublicationOpener(
            parser: DefaultPublicationParser(
                httpClient: httpClient,
                assetRetriever: assetRetriever,
                pdfFactory: DefaultPDFDocumentFactory()
            )
        )

        switch await assetRetriever.retrieve(url: assetURL) {
        case let .failure(error):
            state = .failed(String(describing: error))
            log.error("ReadiumEPUB retrieve failed: \(String(describing: error), privacy: .public)")
        case let .success(asset):
            switch await opener.open(asset: asset, allowUserInteraction: false) {
            case let .failure(error):
                state = .failed(String(describing: error))
                log.error("ReadiumEPUB open failed: \(String(describing: error), privacy: .public)")
            case let .success(publication):
                state = .ready(publication)
                log.info("ReadiumEPUB opened: \(publication.metadata.title ?? "untitled", privacy: .public)")
            }
        }
    }

    // MARK: - Preferences mapping (pure)

    /// Translates vreader's `EPUBLayoutPreference` into a Readium
    /// `EPUBPreferences`. `.scroll` → continuous vertical scroll
    /// (`scroll: true`); `.paged` → horizontal paginated (`scroll: false`).
    /// Pure + static so the mapping is unit-testable without a render.
    nonisolated static func epubPreferences(for layout: EPUBLayoutPreference) -> EPUBPreferences {
        EPUBPreferences(scroll: layout == .scroll)
    }
}
