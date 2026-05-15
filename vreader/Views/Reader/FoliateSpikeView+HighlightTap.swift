// Purpose: Tap-on-highlight handling for FoliateSpikeView (AZW3/MOBI).
// Bug #199 / GH #733 — extracted from FoliateSpikeView.swift to keep the
// host view under the project's ~300-line guideline.
//
// Flow:
//   1. Foliate-js fires `annotation-show` when the user taps an existing
//      highlight (caught by the Coordinator in FoliateSpikeView.swift, which
//      posts `.foliateAnnotationTapRequested` with the CFI + fingerprintKey).
//   2. The view-modifier here observes that notification, resolves the CFI
//      to the persisted highlight's UUID via `FoliateHighlightTapResolver`,
//      posts the cross-format `.readerHighlightTapped` event so non-UI
//      observers (annotations panel) react, and presents the inline
//      edit/delete menu via `HighlightActionPresenting`.
//   3. On Delete, persistence delete + `.readerHighlightRemoved` + a
//      `.foliateRequestAnnotationJSDelete` notification that the Coordinator
//      picks up to evaluate `readerAPI.deleteAnnotation` on the live
//      WKWebView so the rendered annotation disappears immediately.
//
// @coordinates-with: FoliateSpikeView.swift, FoliateHighlightTapResolver.swift,
//   FoliateHighlightRenderer.swift, ReaderNotifications.swift,
//   HighlightActionPresenting.swift, PersistenceActor+Highlights.swift

import SwiftUI
import SwiftData
import OSLog
import UIKit

// MARK: - Anchor view helper

enum FoliateHighlightTapAnchor {
    /// Returns a UIView to anchor the inline edit/delete menu against.
    /// Uses the key window's root view — sub-optimal anchor (menu appears
    /// at the view origin rather than at the tapped highlight) but
    /// functional. Optimal anchoring needs foliate-host.js to forward the
    /// annotation's screen rect, which is a future iteration.
    @MainActor
    static func resolveAnchorView() -> UIView? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene,
                  windowScene.activationState == .foregroundActive else { continue }
            for window in windowScene.windows where window.isKeyWindow {
                return window.rootViewController?.view ?? window
            }
        }
        return nil
    }
}

// MARK: - ViewModifier

/// Attaches the `.foliateAnnotationTapRequested` observer to a view, so the
/// outer SwiftUI scope (where `modelContext` is available) can perform the
/// resolver fetch + present the inline menu. Extracted so the host view
/// body stays small.
struct FoliateHighlightTapHandlerModifier: ViewModifier {
    let fingerprintKey: String?
    let highlightActionPresenter: (any HighlightActionPresenting)?
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: .foliateAnnotationTapRequested)
        ) { notification in
            handle(notification)
        }
    }

    private func handle(_ notification: Notification) {
        guard let info = notification.userInfo,
              let cfi = info["cfi"] as? String,
              let key = info["fingerprintKey"] as? String,
              key == fingerprintKey else { return }
        let presenter = highlightActionPresenter
        let persistence = PersistenceActor(modelContainer: modelContext.container)
        Task { @MainActor in
            do {
                let records = try await persistence.fetchHighlights(forBookWithKey: key)
                guard let highlightID = FoliateHighlightTapResolver.resolveHighlightID(
                    forCFI: cfi, in: records
                ) else { return }
                let event = ReaderHighlightTapEvent(highlightID: highlightID, sourceRect: .zero)
                NotificationCenter.default.post(name: .readerHighlightTapped, object: event)
                // Bug #199: present the inline edit/delete menu when wired.
                // `sourceRect` stays `.zero` (no rect-forwarding in foliate-host.js
                // yet), so the menu anchors at the view origin — known sub-optimal.
                guard let presenter = presenter,
                      let anchorView = FoliateHighlightTapAnchor.resolveAnchorView()
                else { return }
                presenter.present(for: event, in: anchorView) { action in
                    guard action == .delete else { return }
                    Task { @MainActor in
                        await Self.performDelete(
                            highlightID: highlightID,
                            cfi: cfi,
                            fingerprintKey: key,
                            persistence: persistence
                        )
                    }
                }
            } catch {
                let log = Logger(subsystem: "com.vreader.app", category: "FoliateSpikeView")
                log.error("annotation-tap resolver fetch failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Persist the deletion, then — only on success — notify observers and
    /// request that the Coordinator strip the rendered annotation from the
    /// Foliate-js overlay. A failed persistence delete must NOT clear the
    /// UI / WebView, otherwise persisted state and rendered state drift
    /// (Codex audit round 1 finding).
    private static func performDelete(
        highlightID: UUID,
        cfi: String,
        fingerprintKey: String,
        persistence: PersistenceActor
    ) async {
        do {
            try await persistence.removeHighlight(highlightId: highlightID)
        } catch {
            let log = Logger(subsystem: "com.vreader.app", category: "FoliateSpikeView")
            log.error("removeHighlight failed; keeping highlight visible: \(String(describing: error), privacy: .public)")
            return
        }
        NotificationCenter.default.post(
            name: .readerHighlightRemoved,
            object: highlightID.uuidString
        )
        NotificationCenter.default.post(
            name: .foliateRequestAnnotationJSDelete,
            object: nil,
            userInfo: ["cfi": cfi, "fingerprintKey": fingerprintKey]
        )
    }
}

extension View {
    func foliateHighlightTapHandler(
        fingerprintKey: String?,
        presenter: (any HighlightActionPresenting)?
    ) -> some View {
        modifier(FoliateHighlightTapHandlerModifier(
            fingerprintKey: fingerprintKey,
            highlightActionPresenter: presenter
        ))
    }
}
