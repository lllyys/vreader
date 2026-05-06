// Purpose: SwiftUI container for the Foliate-js reader (AZW3/MOBI, later EPUB).
// Composes FoliateViewBridge (WKWebView) with loading/error overlays, reading
// progress, and navigation controls.
//
// Key decisions:
// - Follows EPUBReaderContainerView pattern: ZStack with loading/error/content layers.
// - ViewModel passed as non-optional let (SwiftUI observes via @Observable).
// - Error display driven by viewModel.errorMessage via .onChange + @State showError.
// - Pure logic extracted to FoliateContainerErrorLogic, FoliateSelectionMapper,
//   FoliateNavigationHelper for testability.
// - Chrome toggle via .readerContentTapped notification (same as EPUB/PDF/TXT).
// - Bookmark via .readerBookmarkRequested notification.
// - FoliateViewBridge wired with all bridge callbacks routed to ViewModel/handlers.
// - lastLocationCFI passed from host for position restore on book-ready.
//
// @coordinates-with: FoliateReaderViewModel.swift, FoliateViewBridge.swift,
//   FoliateTypes.swift, FoliateReaderContainerView+Highlights.swift,
//   FoliateReaderContainerView+Navigation.swift,
//   ReaderFormatHosts.swift

#if canImport(UIKit)
import SwiftUI
import SwiftData
import UIKit

/// Container view for the Foliate-js reader screen (AZW3/MOBI formats).
struct FoliateReaderContainerView: View {
    let fileURL: URL
    let viewModel: FoliateReaderViewModel
    var settingsStore: ReaderSettingsStore?
    var modelContainer: ModelContainer?
    var ttsService: TTSService?
    /// Saved CFI to restore on book-ready. Passed from FoliateReaderHost after loading position.
    var lastLocationCFI: String?

    @State private var showError = false
    /// Controls whether the bottom overlay is visible (mirrors chrome toggle).
    @State private var isChromeVisible = true
    /// Pending text selection event for the highlight action dialog.
    @State var pendingSelectionEvent: FoliateSelectionEvent?
    /// Whether the highlight action sheet is visible.
    @State var showHighlightSheet = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            if viewModel.isLoading {
                loadingView
            } else if viewModel.errorMessage != nil {
                errorView(message: viewModel.errorMessage ?? "Unknown error")
            } else {
                readerContent
            }

            // Bottom navigation overlay
            if !viewModel.isLoading, viewModel.errorMessage == nil, isChromeVisible,
               (ttsService?.state ?? .idle) == .idle {
                VStack(spacing: 0) {
                    Spacer()
                    bottomOverlay
                }
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") { }
        } message: {
            Text(viewModel.errorMessage ?? "Unknown error")
        }
        .onChange(of: viewModel.errorMessage) { _, newValue in
            showError = newValue != nil
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerContentTapped)) { _ in
            isChromeVisible.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerBookmarkRequested)) { _ in
            guard let locator = viewModel.currentLocator(),
                  let container = modelContainer else { return }
            let persistence = PersistenceActor(modelContainer: container)
            Task {
                try? await persistence.addBookmark(
                    locator: locator,
                    title: nil,
                    toBookWithKey: viewModel.bookFingerprintKey
                )
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerNavigateToLocator)) { notification in
            guard let locator = notification.object as? Locator,
                  let cfi = locator.cfi else { return }
            navigateToSearchResult(cfi: cfi)
        }
        .task {
            await viewModel.open()
        }
        .onDisappear {
            let bgTaskID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
            Task {
                await viewModel.close()
                if bgTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTaskID)
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background, .inactive:
                let bgTaskID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
                Task {
                    await viewModel.onBackground()
                    if bgTaskID != .invalid {
                        UIApplication.shared.endBackgroundTask(bgTaskID)
                    }
                }
            case .active:
                viewModel.onForeground()
            @unknown default:
                break
            }
        }
        .confirmationDialog(
            "Text Selection",
            isPresented: $showHighlightSheet,
            titleVisibility: .visible
        ) {
            Button("Highlight") {
                guard let event = pendingSelectionEvent else { return }
                // Create highlight using CFI anchor
                let js = FoliateHighlightRenderer.addAnnotationJS(cfi: event.cfi, color: "yellow")
                // TODO: persist highlight to SwiftData + inject JS via bridge
                pendingSelectionEvent = nil
            }
            Button("Copy") {
                guard let event = pendingSelectionEvent else { return }
                UIPasteboard.general.string = event.text
                pendingSelectionEvent = nil
            }
            Button("Cancel", role: .cancel) {
                pendingSelectionEvent = nil
            }
        }
        .accessibilityIdentifier("foliateReaderContainer")
    }

    // MARK: - Subviews

    @ViewBuilder
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
            Text("Opening book\u{2026}")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("foliateReaderLoading")
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .accessibilityIdentifier("foliateReaderError")
    }

    @ViewBuilder
    private var readerContent: some View {
        FoliateViewBridge(
            bookURL: fileURL,
            bookFormat: viewModel.bookFingerprint.format.rawValue,
            fingerprintKey: viewModel.bookFingerprintKey,
            readerToken: nil,
            lastLocationCFI: lastLocationCFI,
            themeCSS: settingsStore.map { store in
                FoliateStyleMapper.themeCSS(
                    fontSize: Int(store.typography.fontSize),
                    lineHeight: Double(store.typography.lineSpacing),
                    fontFamily: nil,
                    textColor: Self.cssColor(store.theme.textColor),
                    backgroundColor: Self.cssColor(store.theme.backgroundColor)
                )
            },
            layoutFlow: "paginated",
            onRelocate: { event in
                viewModel.handleRelocate(event)
                notifyPositionChanged()
            },
            onSelection: { event in handleSelection(event) },
            onBookReady: { info in viewModel.handleBookReady(info.title, sections: info.sections) },
            onCreateOverlay: { index in handleCreateOverlay(sectionIndex: index) },
            onError: { msg in viewModel.handleError(msg) },
            onTap: { NotificationCenter.default.post(name: .readerContentTapped, object: nil) },
            onAnnotationShow: { cfi in handleAnnotationShow(cfi: cfi) },
            onExternalLink: { urlString in
                guard let url = URL(string: urlString),
                      let scheme = url.scheme?.lowercased(),
                      ["http", "https", "mailto"].contains(scheme) else { return }
                UIApplication.shared.open(url)
            }
        )
        .ignoresSafeArea(edges: .bottom)
        .accessibilityIdentifier("foliateReaderContent")
    }

    @ViewBuilder
    var bottomOverlay: some View {
        VStack(spacing: 0) {
            if let label = viewModel.currentTOCLabel {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
            }

            ReaderBottomOverlay(
                progress: viewModel.currentProgress,
                sessionTime: viewModel.sessionTimeDisplay,
                settingsStore: settingsStore,
                accessibilityPrefix: "foliate"
            )
        }
        .accessibilityIdentifier("foliateBottomOverlay")
    }

    // MARK: - Helpers

    /// Converts a UIColor to a CSS rgb() string for Foliate-js style injection.
    private static func cssColor(_ color: UIColor) -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return "rgb(\(Int(r * 255)),\(Int(g * 255)),\(Int(b * 255)))"
    }
}

// MARK: - Pure Logic Extracts (for testability)

/// Pure logic for error display decisions.
enum FoliateContainerErrorLogic {
    /// Whether an error alert should be shown based on the error message.
    static func shouldShowError(errorMessage: String?) -> Bool {
        errorMessage != nil
    }
}

/// Maps Foliate-js selection events to notification payloads.
enum FoliateSelectionMapper {
    /// Converts a FoliateSelectionEvent to a TextSelectionInfo for notifications.
    /// Foliate uses CFI-based positions, so UTF-16 offsets are set to 0.
    static func notificationPayload(from event: FoliateSelectionEvent) -> TextSelectionInfo {
        TextSelectionInfo(
            selectedText: event.text,
            startUTF16: 0,
            endUTF16: 0
        )
    }
}

/// Pure validation logic for navigation targets.
enum FoliateNavigationHelper {
    /// Whether a CFI string is valid for navigation.
    static func isValidNavigationTarget(cfi: String?) -> Bool {
        guard let cfi, !cfi.trimmingCharacters(in: .whitespaces).isEmpty else {
            return false
        }
        return true
    }
}

#endif
