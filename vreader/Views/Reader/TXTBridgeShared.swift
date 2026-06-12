// Purpose: Shared functions for TXTTextViewBridge and TXTChunkedReaderBridge coordinators.
// Extracted from both bridge coordinators (WI-002) — zero logic change.
//
// Key decisions:
// - Selection-notification routing (postSelectionNotification + the WI-12b
//   bilingual mapping and bug-#350 synthetic-start projection) lives in
//   TXTBridgeShared+SelectionMapping.swift.
// - buildReaderEditMenu builds the shared Highlight, Add Note, Define, and Translate menu.
// - postContentTappedNotification extracts the identical tap handler body.
// - gestureRecognizerShouldRecognizeSimultaneously extracts the identical delegate answer.
// - highlightLongPressName + simultaneousRecognitionAllowed gate feature #55 WI-6's
//   long-press recognizer so it stays mutually exclusive with UITextView's native
//   text-selection long-press when the press lands on a persisted highlight.
//
// @coordinates-with TXTTextViewBridge.swift, TXTChunkedReaderBridge.swift,
//   ReaderNotifications.swift, DictionaryLookup.swift

import UIKit

/// Shared utility functions for TXT/MD reader bridge coordinators.
enum TXTBridgeShared {

    /// `UIGestureRecognizer.name` stamped on feature #55 WI-6's highlight
    /// long-press recognizer (TXT non-chunked, chunked, and PDF). The
    /// coordinator's `UIGestureRecognizerDelegate` reads this name to (a)
    /// gate `gestureRecognizerShouldBegin` with a highlight hit-test and
    /// (b) deny simultaneous recognition against the native selection
    /// long-press — so a long-press on a highlight opens ONLY feature
    /// #53's delete menu, never the system text-selection / edit menu.
    static let highlightLongPressName = "vreader.feature55.highlightLongPress"

    /// Builds the shared edit menu with Highlight, Add Note, Define, and
    /// Translate actions.
    ///
    /// - Parameter isAITranslateAvailable: When false, the Translate action is
    ///   omitted entirely. Callers should pass `AIReaderAvailability.isAvailable(...)`
    ///   so that revoking AI consent (bug #90) hides the entry point instead
    ///   of letting the user discover the failure mid-action.
    /// - Parameter bilingualSegmentMap: feature #56 WI-12b — source↔display
    ///   offset map forwarded to every action's `postSelectionNotification`
    ///   call so the menu's selection-actions carry source-domain offsets
    ///   even with bilingual interlinear on. Default identity = byte-
    ///   identical pass-through.
    @MainActor
    static func buildReaderEditMenu(
        range: NSRange,
        textView: UITextView,
        suggestedActions: [UIMenuElement],
        chunkOffset: Int = 0,
        isAITranslateAvailable: Bool = true,
        bilingualSegmentMap: BilingualDisplaySegmentMap =
            BilingualDisplaySegmentMap.identity(sourceLength: 0)
    ) -> UIMenu? {
        guard range.length > 0 else { return UIMenu(children: suggestedActions) }

        let highlightAction = UIAction(
            title: "Highlight",
            image: UIImage(systemName: "highlighter")
        ) { [weak textView] _ in
            guard let textView else { return }
            postSelectionNotification(
                .readerHighlightRequested, from: textView, range: range,
                chunkOffset: chunkOffset, bilingualSegmentMap: bilingualSegmentMap
            )
        }

        let noteAction = UIAction(
            title: "Add Note",
            image: UIImage(systemName: "note.text.badge.plus")
        ) { [weak textView] _ in
            guard let textView else { return }
            postSelectionNotification(
                .readerAnnotationRequested, from: textView, range: range,
                chunkOffset: chunkOffset, bilingualSegmentMap: bilingualSegmentMap
            )
        }

        let defineAction = UIAction(
            title: DictionaryLookup.defineMenuTitle,
            image: UIImage(systemName: "text.book.closed")
        ) { [weak textView] _ in
            guard let textView else { return }
            postSelectionNotification(
                .readerDefineRequested, from: textView, range: range,
                chunkOffset: chunkOffset, bilingualSegmentMap: bilingualSegmentMap
            )
        }

        var lookupChildren: [UIMenuElement] = [defineAction]
        if isAITranslateAvailable {
            let translateAction = UIAction(
                title: DictionaryLookup.translateMenuTitle,
                image: UIImage(systemName: "character.book.closed")
            ) { [weak textView] _ in
                guard let textView else { return }
                postSelectionNotification(
                    .readerTranslateRequested, from: textView, range: range,
                    chunkOffset: chunkOffset, bilingualSegmentMap: bilingualSegmentMap
                )
            }
            lookupChildren.append(translateAction)
        }

        let annotationMenu = UIMenu(
            title: "", options: .displayInline,
            children: [highlightAction, noteAction]
        )
        let lookupMenu = UIMenu(
            title: "", options: .displayInline,
            children: lookupChildren
        )
        return UIMenu(children: [annotationMenu, lookupMenu] + suggestedActions)
    }

    /// Posts the content-tapped notification (toolbar toggle).
    static func postContentTappedNotification() {
        NotificationCenter.default.post(name: .readerContentTapped, object: nil)
    }

    /// Shared gesture recognizer delegate answer — always allow simultaneous recognition.
    static func gestureRecognizerShouldRecognizeSimultaneously() -> Bool {
        true
    }

    /// Feature #55 WI-6 simultaneous-recognition policy. The tap recognizer
    /// keeps the legacy "always allow" answer (it must coexist with
    /// UITextView's own tap handling). The highlight long-press recognizer
    /// — identified by `highlightLongPressName` — instead returns `false`
    /// so it is mutually exclusive with the system text-selection
    /// long-press: a deliberate long-press on a persisted highlight opens
    /// feature #53's delete menu WITHOUT UITextView/PDFView also starting a
    /// selection. (`gestureRecognizerShouldBegin` already keeps the
    /// long-press from beginning on plain body text, so this denial only
    /// ever applies on top of a confirmed highlight hit.)
    ///
    /// - Parameters:
    ///   - gestureName: `gestureRecognizer.name` of the recognizer the
    ///     delegate callback fired for.
    /// - Returns: `false` only when the recognizer is WI-6's highlight
    ///   long-press; `true` otherwise (the pre-WI-6 behavior).
    static func simultaneousRecognitionAllowed(for gestureName: String?) -> Bool {
        gestureName != highlightLongPressName
    }
}
