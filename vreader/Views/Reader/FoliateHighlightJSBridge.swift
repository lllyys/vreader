// Purpose: Feature #64 WI-4 — `FoliateHighlightJSBridge`, the pure-logic
// helper that posts the Foliate recolor / delete JS-notification pairs for
// the unified highlight-action popover.
//
// Foliate (AZW3/MOBI) has NO `HighlightRenderer` conformer —
// `FoliateHighlightRenderer` is a `struct` with only `static` JS-builder
// methods. Foliate highlight visuals are driven entirely by `NotificationCenter`
// messages keyed on CFI, observed inside `FoliateSpikeView.Coordinator`
// (the `.foliateRequestAnnotationJSCreate` / `Delete` observers). So the
// unified popover's Foliate path does NOT go through `HighlightCoordinator`;
// it posts those notifications instead.
//
// This bridge owns the "extract the CFI from a record's `.epub` anchor + post
// the right pair of notifications" logic so it is unit-testable with a
// `NotificationCenter` spy — no `WKWebView`.
//
// Key decisions:
// - `@MainActor` — `NotificationCenter.post` for reader-UI events is driven
//   on the main actor, consistent with the rest of the reader bus.
// - The CFI is recovered from `HighlightRecord.anchor`'s `.epub` case
//   (`AnnotationAnchor.epub(href:cfi:serializedRange:)` carries the CFI —
//   AZW3/MOBI highlights store the `.epub` anchor because Foliate-js is
//   CFI-based). A record whose `anchor` is not `.epub` (legacy / corrupt)
//   skips the JS repaint with an OSLog warning — no crash, no force-unwrap.
//   The next book reopen repaints from persistence.
// - `recolor` posts delete-then-create — Foliate-js replaces an annotation
//   that way. `delete` posts BOTH `.readerHighlightRemoved` (UUID — keeps
//   the panel/list in sync) AND `.foliateRequestAnnotationJSDelete` (CFI —
//   strips the SVG overlay immediately).
//
// @coordinates-with: FoliateSpikeView.swift (the JS observers),
//   FoliateHighlightRenderer.swift, HighlightRecord.swift,
//   AnnotationAnchor.swift, ReaderNotifications.swift
//   (.foliateRequestAnnotationJSCreate / Delete, .readerHighlightRemoved)

#if canImport(UIKit)
import Foundation
import OSLog

/// Posts the Foliate recolor / delete JS-notification pairs for the unified
/// highlight-action popover. Pure logic — testable with a NotificationCenter
/// spy, no `WKWebView`.
@MainActor
struct FoliateHighlightJSBridge {

    private let notificationCenter: NotificationCenter
    private let log = Logger(subsystem: "com.vreader.app", category: "FoliateHighlightJSBridge")

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    /// Repaints a recolored highlight in the Foliate WKWebView: posts
    /// `.foliateRequestAnnotationJSDelete` then `.foliateRequestAnnotationJSCreate`
    /// (delete-then-create — how Foliate-js replaces an annotation) with the
    /// CFI from the record's `.epub` anchor, the new color, and the book key.
    ///
    /// A record whose `anchor` is not `.epub` (legacy / corrupt) skips the JS
    /// repaint with a logged warning — the recolor still persisted; the next
    /// book reopen repaints from persistence.
    func recolor(record: HighlightRecord, to color: String, fingerprintKey: String) {
        guard let cfi = Self.cfi(from: record.anchor) else {
            log.warning("recolor skipped — record has no .epub anchor CFI")
            return
        }
        notificationCenter.post(
            name: .foliateRequestAnnotationJSDelete,
            object: nil,
            userInfo: ["cfi": cfi, "fingerprintKey": fingerprintKey]
        )
        notificationCenter.post(
            name: .foliateRequestAnnotationJSCreate,
            object: nil,
            userInfo: ["cfi": cfi, "color": color, "fingerprintKey": fingerprintKey]
        )
    }

    /// Removes a deleted highlight from the Foliate WKWebView: posts
    /// `.readerHighlightRemoved` (the highlight's UUID string — keeps the
    /// Annotations panel / list in sync) AND, when the record carries an
    /// `.epub` anchor CFI, `.foliateRequestAnnotationJSDelete` (strips the
    /// SVG overlay immediately).
    ///
    /// `.readerHighlightRemoved` is posted unconditionally so the panel
    /// updates even for a legacy non-`.epub`-anchored record; only the JS
    /// overlay strip is skipped (with a logged warning) in that case.
    func delete(record: HighlightRecord, fingerprintKey: String) {
        notificationCenter.post(
            name: .readerHighlightRemoved,
            object: record.highlightId.uuidString
        )
        guard let cfi = Self.cfi(from: record.anchor) else {
            log.warning("delete — SVG overlay strip skipped (record has no .epub anchor CFI)")
            return
        }
        notificationCenter.post(
            name: .foliateRequestAnnotationJSDelete,
            object: nil,
            userInfo: ["cfi": cfi, "fingerprintKey": fingerprintKey]
        )
    }

    /// Extracts the CFI from an anchor's `.epub` case. Returns `nil` for any
    /// other anchor case, a `nil` anchor, or an empty CFI — the caller skips
    /// the JS repaint rather than posting a no-op notification.
    static func cfi(from anchor: AnnotationAnchor?) -> String? {
        guard case let .epub(_, cfi, _) = anchor, !cfi.isEmpty else { return nil }
        return cfi
    }
}
#endif
