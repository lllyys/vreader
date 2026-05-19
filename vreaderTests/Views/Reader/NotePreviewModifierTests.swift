// Purpose: Feature #55 WI-5 — tests for the note-preview presentation wiring:
// `NotePreviewRequest` (the `.readerHighlightTapped` parse helper),
// `NotePreviewSheetView` (the bottom-sheet fallback render), and the
// `NotePreviewPresenting` protocol surface.
//
// The callout-vs-sheet `form(...)` decision is covered separately in
// `NotePreviewPresenterTests`. These tests focus on WI-5's new surface:
//   - `NotePreviewRequest.event(from:)` extracts a `ReaderHighlightTapEvent`
//     and ignores a notification whose `object` is some other type (plan §5).
//   - `NotePreviewSheetView` constructs for the empty and note states.
//   - a fake `NotePreviewPresenting` can be invoked through the protocol.

import Testing
import Foundation
import SwiftUI
import UIKit
import CoreGraphics
@testable import vreader

@Suite("Feature #55 WI-5 — NotePreview presentation wiring")
struct NotePreviewModifierTests {

    static let fp = DocumentFingerprint(
        contentSHA256: "abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        fileByteCount: 1024, format: .epub
    )

    private static func content(note: String?, rect: CGRect = CGRect(x: 1, y: 2, width: 30, height: 14))
        -> NotePreviewContent {
        NotePreviewContent(
            id: UUID(), note: note, highlightedText: "an excerpt",
            colorName: "yellow", createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            sourceRect: rect
        )
    }

    // MARK: - NotePreviewRequest event parsing

    @Test("event(from:) extracts a ReaderHighlightTapEvent object")
    func eventParsesReaderHighlightTapEvent() {
        let id = UUID()
        let rect = CGRect(x: 5, y: 6, width: 40, height: 16)
        let note = Notification(
            name: .readerHighlightTapped,
            object: ReaderHighlightTapEvent(highlightID: id, sourceRect: rect)
        )
        let event = NotePreviewRequest.event(from: note)
        #expect(event?.highlightID == id)
        #expect(event?.sourceRect == rect)
    }

    @Test("event(from:) ignores a notification whose object is not a tap event")
    func eventIgnoresNonEventObject() {
        // A bare string — a bridge mis-posting, or an unrelated notification.
        let stringNote = Notification(name: .readerHighlightTapped, object: "not an event")
        #expect(NotePreviewRequest.event(from: stringNote) == nil)
    }

    @Test("event(from:) ignores a notification with a nil object")
    func eventIgnoresNilObject() {
        let nilNote = Notification(name: .readerHighlightTapped, object: nil)
        #expect(NotePreviewRequest.event(from: nilNote) == nil)
    }

    // MARK: - NotePreviewSheetView render smoke

    @MainActor
    @Test("the sheet view constructs for the note state without crashing")
    func sheetRenderSmokeNoteState() {
        let view = NotePreviewSheetView(
            content: Self.content(note: "a long note body"),
            theme: .paper,
            onAction: { _ in },
            onDismiss: {}
        )
        let host = UIHostingController(rootView: view)
        host.loadViewIfNeeded()
        #expect(host.view != nil)
    }

    @MainActor
    @Test("the sheet view constructs for the empty state without crashing")
    func sheetRenderSmokeEmptyState() {
        let view = NotePreviewSheetView(
            content: Self.content(note: nil),
            theme: .paper,
            onAction: { _ in },
            onDismiss: {}
        )
        let host = UIHostingController(rootView: view)
        host.loadViewIfNeeded()
        #expect(host.view != nil)
    }

    @MainActor
    @Test("the sheet view honors dark theme")
    func sheetRenderSmokeDarkTheme() {
        let view = NotePreviewSheetView(
            content: Self.content(note: "note"),
            theme: .dark,
            onAction: { _ in },
            onDismiss: {}
        )
        let host = UIHostingController(rootView: view)
        host.loadViewIfNeeded()
        #expect(host.view != nil)
    }

    // MARK: - resolvedForm (the modifier's routing decision)

    @Test("resolvedForm picks callout for a short anchored note with a host view")
    func resolvedFormCalloutForShortAnchoredWithHost() {
        let form = NotePreviewPresenter.resolvedForm(
            for: Self.content(note: "short"),
            isVoiceOverRunning: false, noteLineCount: 1, hasHostView: true
        )
        #expect(form == .callout)
    }

    @Test("resolvedForm degrades a callout to the sheet when no host view")
    func resolvedFormSheetWhenNoHostView() {
        // form(...) would pick .callout (short note, anchored, no VoiceOver),
        // but with no host UIView to anchor to it must degrade to .sheet.
        let form = NotePreviewPresenter.resolvedForm(
            for: Self.content(note: "short"),
            isVoiceOverRunning: false, noteLineCount: 1, hasHostView: false
        )
        #expect(form == .sheet)
    }

    @Test("resolvedForm keeps the sheet when form already picks sheet, host or not")
    func resolvedFormKeepsSheetRegardlessOfHost() {
        // A long note → sheet — having a host view does not promote it to a callout.
        let withHost = NotePreviewPresenter.resolvedForm(
            for: Self.content(note: "long"),
            isVoiceOverRunning: false, noteLineCount: 12, hasHostView: true
        )
        let withoutHost = NotePreviewPresenter.resolvedForm(
            for: Self.content(note: "long"),
            isVoiceOverRunning: false, noteLineCount: 12, hasHostView: false
        )
        #expect(withHost == .sheet)
        #expect(withoutHost == .sheet)
    }

    @Test("resolvedForm keeps the sheet for VoiceOver even with a host view")
    func resolvedFormVoiceOverStaysSheetWithHost() {
        let form = NotePreviewPresenter.resolvedForm(
            for: Self.content(note: "short"),
            isVoiceOverRunning: true, noteLineCount: 1, hasHostView: true
        )
        #expect(form == .sheet)
    }

    @Test("resolvedForm keeps the sheet for a zero sourceRect even with a host view")
    func resolvedFormZeroRectStaysSheetWithHost() {
        let form = NotePreviewPresenter.resolvedForm(
            for: Self.content(note: "short", rect: .zero),
            isVoiceOverRunning: false, noteLineCount: 1, hasHostView: true
        )
        #expect(form == .sheet)
    }

    // MARK: - NotePreviewPresenting protocol surface

    @MainActor
    @Test("a NotePreviewPresenting conformer can be invoked through the protocol")
    func presentingProtocolIsInvokable() {
        let fake = FakeNotePreviewPresenter()
        let presenter: any NotePreviewPresenting = fake
        let host = UIView()
        presenter.presentCallout(
            Self.content(note: "note"),
            theme: .paper,
            in: host,
            onAction: { _ in },
            onDismiss: {}
        )
        #expect(fake.presentCalloutCallCount == 1)
        #expect(fake.lastContent?.note == "note")
    }

    @MainActor
    @Test("dismissCallout routes through the protocol")
    func presentingProtocolDismiss() {
        let fake = FakeNotePreviewPresenter()
        let presenter: any NotePreviewPresenting = fake
        presenter.dismissCallout()
        #expect(fake.dismissCalloutCallCount == 1)
    }

    @MainActor
    @Test("dismissCallout(completion:) runs the completion")
    func presentingProtocolDismissCompletionRuns() {
        let fake = FakeNotePreviewPresenter()
        let presenter: any NotePreviewPresenting = fake
        var completionRan = false
        presenter.dismissCallout(completion: { completionRan = true })
        #expect(fake.dismissCalloutCallCount == 1)
        #expect(completionRan)
    }
}

// MARK: - Test double

/// A `NotePreviewPresenting` fake — records calls instead of presenting a
/// real popover, so the wiring can be unit-tested without UIKit chrome.
@MainActor
private final class FakeNotePreviewPresenter: NotePreviewPresenting {
    private(set) var presentCalloutCallCount = 0
    private(set) var dismissCalloutCallCount = 0
    private(set) var lastContent: NotePreviewContent?

    func presentCallout(
        _ content: NotePreviewContent,
        theme: ReaderThemeV2,
        in view: UIView,
        onAction: @escaping (NoteCalloutAction) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        presentCalloutCallCount += 1
        lastContent = content
    }

    func dismissCallout(completion: (@MainActor () -> Void)?) {
        dismissCalloutCallCount += 1
        completion?()
    }
}
