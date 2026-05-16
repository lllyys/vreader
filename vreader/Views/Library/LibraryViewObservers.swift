// Purpose: Feature #60 WI-9 — the notification-observer chain for the
// re-skinned `LibraryView`. Extracted into a dedicated `ViewModifier`
// because applying every `.onReceive` inline pushes the `LibraryView`
// body past the Swift type-checker's complexity ceiling.
//
// Behavior is preserved verbatim from the pre-#60 `LibraryView`:
// - Feature #47 WI-6 lazy-download row-tap handler.
// - `.readerDidClose` → in-memory last-read update (bug #45 v4).
// - `.bookFileStateDidChange` → force-refresh (bug #115 / #47 WI-4b).
// - `.bookDidImport` → force-refresh (bug #197).
// - DEBUG: `.debugBridgeOpenBook` / `.debugBridgeLibraryChanged`
//   (feature #44 DebugBridge).
//
// @coordinates-with: LibraryView.swift, LibraryViewModel.swift,
//   LazyDownloadCoordinator.swift, WebDAVProviderFactory.swift,
//   ReaderNotifications.swift, DebugBridgeNotifications.swift

import SwiftUI
import OSLog

private let log = Logger(subsystem: "com.vreader.app", category: "LibraryViewObservers")

/// The notification-observer chain for the re-skinned `LibraryView`.
struct LibraryViewObservers: ViewModifier {
    @Environment(\.lazyDownloadCoordinator) private var lazyDownloadCoordinator
    @Environment(\.webDAVNetworkPolicy) private var webDAVNetworkPolicy

    let viewModel: LibraryViewModel
    @Binding var bookForDownloadSheet: LibraryBookItem?
    @Binding var isPushingReader: Bool
    @Binding var navigationPath: NavigationPath

    func body(content: Content) -> some View {
        content
            // Feature #47 WI-6: row tap on a non-`.local` row → kick off
            // a lazy download. Posted from `LibraryView.openBook(_:)`.
            .onReceive(NotificationCenter.default.publisher(for: .libraryRowTappedWhileNotLocal)) { notification in
                handleRowTapWhileNotLocal(notification)
            }
            .onReceive(NotificationCenter.default.publisher(for: .readerDidClose)) { notification in
                // Bug #45 v4: update in-memory lastReadAt and re-sort
                // immediately. Do NOT call loadBooks() — it re-fetches
                // from DB before recomputeStats() commits, overwriting
                // the in-memory fix.
                if let key = notification.object as? String {
                    viewModel.markBookAsJustRead(fingerprintKey: key)
                } else {
                    Task { await viewModel.refresh(force: true) }
                }
            }
            // Bug #115 (#47 WI-4b): when the lazy-download finalizer
            // flips a row from `.remoteOnly` to `.local`, refresh the
            // library so the row reflects the new state immediately.
            .onReceive(NotificationCenter.default.publisher(for: .bookFileStateDidChange)) { _ in
                Task { await viewModel.refresh(force: true) }
            }
            // Bug #197: BookImporter posts `.bookDidImport` after every
            // import. The Share-Sheet / system-Open-in path does not
            // call `loadBooks()` directly, so this keeps the library in
            // sync without a cold launch.
            .onReceive(NotificationCenter.default.publisher(for: .bookDidImport)) { _ in
                Task { await viewModel.refresh(force: true) }
            }
            .modifier(LibraryDebugBridgeObservers(
                viewModel: viewModel,
                isPushingReader: $isPushingReader,
                navigationPath: $navigationPath
            ))
    }

    // MARK: - Feature #47 lazy-download row-tap

    /// Handles a tap on a non-`.local` row by enqueuing a lazy
    /// download. Mirrors the pre-#60 `LibraryView` handler verbatim;
    /// errors surface through `viewModel.setError`.
    private func handleRowTapWhileNotLocal(_ notification: Notification) {
        log.info("rowTap observer fired")
        guard let key = notification.userInfo?["fingerprintKey"] as? String else {
            log.error("rowTap observer: missing fingerprintKey in userInfo")
            return
        }
        guard let book = viewModel.books.first(where: { $0.fingerprintKey == key }) else {
            log.error("rowTap observer: book not found in viewModel.books for key=\(key, privacy: .public)")
            return
        }
        guard book.needsDownload else {
            log.error("rowTap observer: book.needsDownload=false for fileState=\(book.fileState.rawValue, privacy: .public)")
            return
        }
        guard let blobPath = book.blobPath else {
            log.error("rowTap observer: book.blobPath is nil for \(key, privacy: .public)")
            return
        }
        guard let coordinator = lazyDownloadCoordinator else {
            log.error("rowTap observer: lazyDownloadCoordinator is nil from Environment")
            return
        }
        guard let policy = webDAVNetworkPolicy else {
            log.error("rowTap observer: webDAVNetworkPolicy is nil from Environment")
            return
        }
        log.info("rowTap observer: all guards passed; coordinator + policy + blobPath OK")
        // fingerprintKey shape: "<format>:<sha256>:<byteCount>"
        let parts = book.fingerprintKey.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3, let bytes = Int64(parts[2]) else { return }
        let sha = String(parts[1])
        let ext = (BookFormat(rawValue: book.format)?.fileExtensions.first) ?? book.format
        Task {
            let builder: WebDAVDownloadRequestBuilder
            do {
                builder = try await WebDAVProviderFactory.makeRequestBuilder(
                    profileStore: WebDAVServerProfileStore.shared
                )
            } catch {
                viewModel.setError("Cannot start download: \(error.localizedDescription)")
                return
            }
            let result = coordinator.enqueue(
                fingerprintKey: book.fingerprintKey,
                blobPath: blobPath,
                expectedSHA256: sha,
                expectedByteCount: bytes,
                originalExtension: ext,
                requestBuilder: builder,
                policy: policy
            )
            switch result {
            case .deferredWiFi:
                viewModel.setError("Wi-Fi only — turn on the toggle in Backup settings to allow cellular.")
            case .notReady:
                viewModel.setError("Lazy-download coordinator unavailable.")
            case .taskDescriptionEncodeFailed:
                viewModel.setError("Internal error encoding download task.")
            case .started:
                bookForDownloadSheet = book
            }
        }
    }
}

/// DEBUG-only DebugBridge observers — split into a separate modifier so
/// the `#if DEBUG` guard wraps a single, self-contained surface (rule
/// 50 §11: DEBUG-only code in dedicated `#if DEBUG` blocks).
private struct LibraryDebugBridgeObservers: ViewModifier {
    let viewModel: LibraryViewModel
    @Binding var isPushingReader: Bool
    @Binding var navigationPath: NavigationPath

    func body(content: Content) -> some View {
        #if DEBUG
        content
            // Feature #44 DebugBridge — vreader-debug://open posts this
            // so automated tests can navigate without tapping. Refresh
            // viewModel.books FIRST so a rapid seed → open finds the
            // freshly-imported book.
            .onReceive(NotificationCenter.default.publisher(for: .debugBridgeOpenBook)) { notification in
                guard let key = notification.userInfo?["fingerprintKey"] as? String else { return }
                Task {
                    await viewModel.loadBooks()
                    guard let book = viewModel.books.first(where: { $0.fingerprintKey == key })
                    else { return }
                    isPushingReader = true
                    navigationPath.append(book)
                }
            }
            // The bridge's reset/seed mutate SwiftData directly; refresh
            // the in-memory books array so the UI reflects the new state.
            .onReceive(NotificationCenter.default.publisher(for: .debugBridgeLibraryChanged)) { _ in
                Task { await viewModel.refresh(force: true) }
            }
        #else
        content
        #endif
    }
}
