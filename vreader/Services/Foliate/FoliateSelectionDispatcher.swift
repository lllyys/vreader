// Purpose: Bug #201 / GH #739 — pure-logic helper that builds the
// notification `userInfo` payload for a Foliate text-selection event.
// Isolates the parse → route hand-off from WKWebView / NotificationCenter
// machinery so the contract is testable in isolation.
//
// Live call site: `FoliateSpikeView.Coordinator.handleMessage` on
// `case "selection":` — parses the raw JS message body via
// `FoliateMessageParser.parseSelection`, then calls into this dispatcher
// to compute the payload, then posts `.foliateSelectionDetected`.
//
// Why a separate type:
// - The coordinator is a private nested class inside `FoliateSpikeView`
//   (a SwiftUI `View`), so the bridge code is awkward to test directly.
// - The bug is small but cross-format: AZW3/MOBI rendering uses Foliate,
//   which shares CFI semantics with EPUB but has different identity
//   plumbing (foliate-host.js sends events with `cfi + text + sectionIndex
//   + rect`, no DOM range). Pinning the payload shape here keeps the
//   contract explicit.
//
// @coordinates-with: FoliateSpikeView.swift, FoliateMessageParser.swift,
//   ReaderNotifications.swift (`.foliateSelectionDetected`),
//   FoliateSpikeView+Selection.swift (outer-view observer)

import Foundation

enum FoliateSelectionDispatcher {

    /// Build the `userInfo` for a `.foliateSelectionDetected`
    /// notification. Returns `nil` when the caller has no identity to
    /// route the highlight against (nil or empty `fingerprintKey`) —
    /// the outer-view observer cannot persist the highlight without
    /// knowing which book it belongs to.
    ///
    /// Why we don't synthesize a default identity here: a Foliate
    /// selection that arrives before the book's fingerprint is known
    /// is a setup race the persistence layer can't repair downstream.
    /// Bailing at the dispatcher prevents a half-formed highlight from
    /// being persisted under the wrong book key.
    static func notificationUserInfo(
        event: FoliateSelectionEvent,
        fingerprintKey: String?
    ) -> [AnyHashable: Any]? {
        guard let key = fingerprintKey, !key.isEmpty else {
            return nil
        }
        return [
            "cfi": event.cfi,
            "text": event.text,
            "fingerprintKey": key,
            "sectionIndex": event.sectionIndex,
        ]
    }
}
