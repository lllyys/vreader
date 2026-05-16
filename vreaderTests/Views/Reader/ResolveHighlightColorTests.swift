// Purpose: Feature #60 WI-7c2 — pins the contract for
// `resolveHighlightColor(from:)` (in ReaderNotifications.swift),
// the consumer-side helper that lets the highlight pipeline honor
// the chosen color when the new SelectionPopover is the producer
// (WI-7b's `SelectionPopoverActionRouter`) while staying
// backward-compatible with legacy producers (the UIMenu callers
// from chunked TXT / MD bridges before WI-7c3..7c5 land).
//
// Why a free function and not inline in `ReaderNotificationModifier`:
// the modifier is a SwiftUI ViewModifier — its `.onReceive` closure
// isn't directly callable from tests. Extracting the
// `Notification → color` mapping makes the contract testable and
// gives future WIs a single seam to evolve if the userInfo schema
// drifts (e.g., a `NamedHighlightColor` enum value instead of a
// raw string).

#if canImport(UIKit)
import Testing
import Foundation
@testable import vreader

@Suite("Feature #60 WI-7c2 — resolveHighlightColor")
@MainActor
struct ResolveHighlightColorTests {

    @Test("uses userInfo[\"color\"] when present and String")
    func usesUserInfoColor() {
        // The post-popover producer (SelectionPopoverActionRouter)
        // sets userInfo["color"] to the chosen NamedHighlightColor.
        // The consumer must thread that value through to the
        // persistence layer.
        for color in ["yellow", "pink", "green", "blue"] {
            let note = Notification(
                name: .readerHighlightRequested,
                object: nil,
                userInfo: ["color": color]
            )
            #expect(resolveHighlightColor(from: note) == color)
        }
    }

    @Test("falls back to \"yellow\" when userInfo is nil (legacy producer)")
    func fallsBackWhenUserInfoMissing() {
        // The legacy UIMenu callers (chunked TXT / MD bridges
        // before WI-7c3..7c5 swap) post via the existing
        // `TXTBridgeShared.postSelectionNotification` API which
        // omits userInfo entirely. The fallback preserves
        // pre-WI-7c behavior.
        let note = Notification(
            name: .readerHighlightRequested,
            object: nil,
            userInfo: nil
        )
        #expect(resolveHighlightColor(from: note) == "yellow")
    }

    @Test("falls back to \"yellow\" when userInfo has no \"color\" key")
    func fallsBackWhenColorMissing() {
        let note = Notification(
            name: .readerHighlightRequested,
            object: nil,
            userInfo: ["unrelated": "value"]
        )
        #expect(resolveHighlightColor(from: note) == "yellow")
    }

    @Test("falls back to \"yellow\" when \"color\" is not a String")
    func fallsBackOnWrongType() {
        // Defensive: a drifted producer (or a misuse) might post
        // an Int or a NamedHighlightColor enum value. Until the
        // contract widens to accept either, treat non-String as
        // missing and fall back rather than crash.
        let note = Notification(
            name: .readerHighlightRequested,
            object: nil,
            userInfo: ["color": 42]
        )
        #expect(resolveHighlightColor(from: note) == "yellow")
    }
}
#endif
