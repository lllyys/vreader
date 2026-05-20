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
//      and posts the cross-format `.readerHighlightTapped` event.
//
// Feature #64 WI-9: a tap on an annotated AZW3/MOBI highlight opens the
// unified highlight-action popover — `HighlightPopoverModifier` (attached on
// `FoliateSpikeView`) observes `.readerHighlightTapped`. The popover's delete
// action routes through `FoliateHighlightMutator`, which posts the CFI-keyed
// `.foliateRequestAnnotationJSDelete` so the rendered SVG overlay is stripped
// immediately (the `FoliateHighlightJSBridge` path). AZW3/MOBI has no native
// long-press recognizer for a web-rendered highlight, so — unlike the native
// TXT/MD/PDF bridges — there was never a feature-#53 long-press `UIMenu` here
// to remove. NOTE — a delete from the Annotations *panel* (not the popover)
// still does not strip the live overlay: the panel posts
// `.readerHighlightRemoved` carrying only the UUID, the Foliate JS strip needs
// the CFI, and the record is already deleted by then; the overlay refreshes on
// the next book reload (tracked as a separate bug).
//
// @coordinates-with: FoliateSpikeView.swift, FoliateHighlightTapResolver.swift,
//   FoliateHighlightRenderer.swift, ReaderNotifications.swift,
//   PersistenceActor+Highlights.swift

import SwiftUI
import SwiftData
import OSLog
import UIKit

// MARK: - ViewModifier

/// Attaches the `.foliateAnnotationTapRequested` observer to a view, so the
/// outer SwiftUI scope (where `modelContext` is available) can perform the
/// resolver fetch + post the cross-format `.readerHighlightTapped` event.
/// Extracted so the host view body stays small.
struct FoliateHighlightTapHandlerModifier: ViewModifier {
    let fingerprintKey: String?
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
        let persistence = PersistenceActor(modelContainer: modelContext.container)
        Task { @MainActor in
            do {
                let records = try await persistence.fetchHighlights(forBookWithKey: key)
                guard let highlightID = FoliateHighlightTapResolver.resolveHighlightID(
                    forCFI: cfi, in: records
                ) else { return }
                // `sourceRect` stays `.zero` — foliate-host.js does not
                // forward the annotation's screen rect, so the unified
                // popover's `resolvedForm` resolves to the bottom-sheet form
                // (no anchor needed). Rect-forwarding for an anchored-card
                // popover is a deferred follow-up.
                let event = ReaderHighlightTapEvent(highlightID: highlightID, sourceRect: .zero)
                NotificationCenter.default.post(name: .readerHighlightTapped, object: event)
            } catch {
                let log = Logger(subsystem: "com.vreader.app", category: "FoliateSpikeView")
                log.error("annotation-tap resolver fetch failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}

extension View {
    func foliateHighlightTapHandler(fingerprintKey: String?) -> some View {
        modifier(FoliateHighlightTapHandlerModifier(fingerprintKey: fingerprintKey))
    }
}
