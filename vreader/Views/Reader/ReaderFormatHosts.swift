// Purpose: Format-specific host views that own ViewModel lifecycle via @State.
// Each host creates its ViewModel on appear and passes it to the format container.
// Extracted from ReaderContainerView (WI-004) to reduce file size.
//
// @coordinates-with ReaderContainerView.swift, TXTReaderContainerView.swift,
//   PDFReaderContainerView.swift, MDReaderContainerView.swift,
//   EPUBReaderContainerView.swift, FoliateReaderContainerView.swift

#if canImport(UIKit)
import SwiftUI
import SwiftData
import UIKit

/// Owns TXTReaderViewModel lifecycle via @State.
struct TXTReaderHost: View {
    let fileURL: URL
    let fingerprint: DocumentFingerprint
    let modelContainer: ModelContainer
    let settingsStore: ReaderSettingsStore
    let ttsService: TTSService
    var tocEntries: [TOCEntry] = []

    @State private var viewModel: TXTReaderViewModel?

    var body: some View {
        Group {
            if let viewModel {
                TXTReaderContainerView(fileURL: fileURL, viewModel: viewModel, settingsStore: settingsStore, modelContainer: modelContainer, ttsService: ttsService, tocEntries: tocEntries)
            } else {
                ProgressView()
            }
        }
        .task {
            guard viewModel == nil else { return }
            let persistence = PersistenceActor(modelContainer: modelContainer)
            let tracker = ReadingSessionTracker(
                clock: SystemClock(),
                store: SwiftDataSessionStore(modelContainer: modelContainer),
                deviceId: ReaderContainerView.deviceId
            )
            viewModel = TXTReaderViewModel(
                bookFingerprint: fingerprint,
                txtService: TXTService(),
                positionStore: persistence,
                sessionTracker: tracker,
                deviceId: ReaderContainerView.deviceId
            )
        }
    }
}

/// Owns PDFReaderViewModel lifecycle via @State.
struct PDFReaderHost: View {
    let fileURL: URL
    let fingerprint: DocumentFingerprint
    let modelContainer: ModelContainer
    let ttsService: TTSService
    /// Bug #198: settingsStore threaded so the PDF reader can theme the
    /// PDFView gutter on Light / Sepia / Dark switches. Optional to keep
    /// previews and ad-hoc test harnesses source-compatible.
    var settingsStore: ReaderSettingsStore?

    @State private var viewModel: PDFReaderViewModel?

    var body: some View {
        Group {
            if let viewModel {
                PDFReaderContainerView(fileURL: fileURL, viewModel: viewModel, modelContainer: modelContainer, ttsService: ttsService, settingsStore: settingsStore)
            } else {
                ProgressView()
            }
        }
        .task {
            guard viewModel == nil else { return }
            let persistence = PersistenceActor(modelContainer: modelContainer)
            let tracker = ReadingSessionTracker(
                clock: SystemClock(),
                store: SwiftDataSessionStore(modelContainer: modelContainer),
                deviceId: ReaderContainerView.deviceId
            )
            viewModel = PDFReaderViewModel(
                bookFingerprint: fingerprint,
                positionStore: persistence,
                sessionTracker: tracker,
                deviceId: ReaderContainerView.deviceId
            )
        }
    }
}

/// Owns MDReaderViewModel lifecycle via @State.
struct MDReaderHost: View {
    let fileURL: URL
    let fingerprint: DocumentFingerprint
    let modelContainer: ModelContainer
    let settingsStore: ReaderSettingsStore
    let ttsService: TTSService

    @State private var viewModel: MDReaderViewModel?

    var body: some View {
        Group {
            if let viewModel {
                MDReaderContainerView(fileURL: fileURL, viewModel: viewModel, settingsStore: settingsStore, modelContainer: modelContainer, ttsService: ttsService)
            } else {
                ProgressView()
            }
        }
        .task {
            guard viewModel == nil else { return }
            let persistence = PersistenceActor(modelContainer: modelContainer)
            let tracker = ReadingSessionTracker(
                clock: SystemClock(),
                store: SwiftDataSessionStore(modelContainer: modelContainer),
                deviceId: ReaderContainerView.deviceId
            )
            viewModel = MDReaderViewModel(
                bookFingerprint: fingerprint,
                parser: MDParser(),
                positionStore: persistence,
                sessionTracker: tracker,
                deviceId: ReaderContainerView.deviceId
            )
        }
    }
}

/// Owns EPUBReaderViewModel lifecycle via @State.
///
/// Bug #252 / GH #1089: the close lifecycle (`viewModel.close()` ending
/// the reading session AND closing the EPUB parser) is owned by the
/// host's `.onDisappear`, NOT by the inner `EPUBReaderContainerView`.
/// The viewModel + parser are `@State` here, so they outlive transient
/// re-mounts of the inner container; closing them on the inner's
/// disappear races the inner's next mount and the new mount fails with
/// `.notOpen` against the parser. Tying the close to the resource owner
/// (this host) makes the lifecycle correct: the close fires only when
/// the host genuinely leaves the hierarchy (navigation pop).
struct EPUBReaderHost: View {
    let fileURL: URL
    let fingerprint: DocumentFingerprint
    let modelContainer: ModelContainer
    let settingsStore: ReaderSettingsStore
    let ttsService: TTSService
    /// Bug #142: per-reader instance token from `ReaderContainerView`,
    /// threaded into `EPUBReaderContainerView` → `EPUBWebViewBridge` →
    /// coordinator's `webView(_:didFinish:)` registry registration.
    var readerToken: UUID?

    @State private var viewModel: EPUBReaderViewModel?
    @State private var parser: EPUBParser?

    var body: some View {
        Group {
            if let viewModel, let parser {
                EPUBReaderContainerView(
                    fileURL: fileURL,
                    viewModel: viewModel,
                    parser: parser,
                    settingsStore: settingsStore,
                    modelContainer: modelContainer,
                    ttsService: ttsService,
                    fingerprintKey: fingerprint.canonicalKey,
                    readerToken: readerToken
                )
            } else {
                ProgressView()
            }
        }
        .task {
            guard viewModel == nil else { return }
            let persistence = PersistenceActor(modelContainer: modelContainer)
            let tracker = ReadingSessionTracker(
                clock: SystemClock(),
                store: SwiftDataSessionStore(modelContainer: modelContainer),
                deviceId: ReaderContainerView.deviceId
            )
            let epubParser = EPUBParser()
            parser = epubParser
            viewModel = EPUBReaderViewModel(
                bookFingerprint: fingerprint,
                parser: epubParser,
                positionStore: persistence,
                sessionTracker: tracker,
                deviceId: ReaderContainerView.deviceId
            )
        }
        .onDisappear {
            // Bug #252 / GH #1089: host-level close lifecycle. The
            // inner `EPUBReaderContainerView.onDisappear` only cancels
            // its in-flight `openTask`; the parser/viewModel close
            // happens here so a transient inner re-mount does not
            // close the shared parser out from under the next mount.
            // Fires only when this host leaves the hierarchy (nav
            // pop) — exactly when ending the reading session +
            // closing the parser is the right behavior.
            guard let viewModel else { return }
            let bgTaskID = UIApplication.shared.beginBackgroundTask(
                expirationHandler: nil
            )
            Task {
                await viewModel.close()
                if bgTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTaskID)
                }
            }
        }
    }
}

/// Owns FoliateReaderViewModel lifecycle for AZW3/MOBI books.
/// Creates persistence dependencies and loads saved position before presenting the container.
struct FoliateReaderHost: View {
    let fileURL: URL
    let fingerprint: DocumentFingerprint
    let modelContainer: ModelContainer
    let settingsStore: ReaderSettingsStore
    let ttsService: TTSService

    @State private var viewModel: FoliateReaderViewModel?
    /// Saved CFI from the last reading session, loaded from persistence.
    @State private var lastLocationCFI: String?

    var body: some View {
        Group {
            if let viewModel {
                FoliateReaderContainerView(
                    fileURL: fileURL,
                    viewModel: viewModel,
                    settingsStore: settingsStore,
                    modelContainer: modelContainer,
                    ttsService: ttsService,
                    lastLocationCFI: lastLocationCFI
                )
            } else {
                ProgressView("Opening book...")
            }
        }
        .task {
            guard viewModel == nil else { return }
            let persistence = PersistenceActor(modelContainer: modelContainer)
            let tracker = ReadingSessionTracker(
                clock: SystemClock(),
                store: SwiftDataSessionStore(modelContainer: modelContainer),
                deviceId: ReaderContainerView.deviceId
            )

            // Load saved position before creating ViewModel.
            if let savedPosition = try? await persistence.loadPosition(
                bookFingerprintKey: fingerprint.canonicalKey
            ) {
                lastLocationCFI = savedPosition.cfi
            }

            viewModel = FoliateReaderViewModel(
                bookFingerprint: fingerprint,
                positionStore: persistence,
                sessionTracker: tracker,
                deviceId: ReaderContainerView.deviceId
            )
        }
    }
}
#endif
