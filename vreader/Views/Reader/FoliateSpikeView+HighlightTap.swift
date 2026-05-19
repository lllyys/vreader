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
// Feature #55 WI-7: a tap on an annotated AZW3/MOBI highlight now opens the
// #55 note preview — `NotePreviewModifier` (attached on `FoliateSpikeView`)
// observes `.readerHighlightTapped`. The legacy #53 tap-time inline
// delete menu is dropped for AZW3/MOBI v1. Highlight deletion is still
// reachable from the Annotations panel's Highlights tab (the note preview's
// "Open in panel" action routes there): the panel swipe-delete removes the
// highlight from persistence and from the panel list. NOTE — the AZW3/MOBI
// *rendered* annotation overlay is not stripped by the panel delete; it
// refreshes on the next book reload. (The panel posts `.readerHighlightRemoved`,
// which carries only the UUID; the Foliate JS strip needs the CFI, and the
// record is already deleted by then — tracked as a separate bug.) AZW3/MOBI
// has no native long-press recognizer for a web-rendered highlight, so —
// unlike TXT/MD/PDF (WI-6) — there is no `present(...)` call to re-home onto
// a long-press; a JS long-press → #53 menu is a deferred follow-up (plan §9).
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
                // Feature #55 WI-7: `sourceRect` stays `.zero` — foliate-host.js
                // does not forward the annotation's screen rect, so
                // `NotePreviewPresenter` resolves the preview to the bottom-sheet
                // form (no anchor needed). Rect-forwarding for a callout-anchored
                // preview is a deferred follow-up (plan §9).
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
