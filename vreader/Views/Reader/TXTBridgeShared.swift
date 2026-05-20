// Purpose: Shared functions for TXTTextViewBridge and TXTChunkedReaderBridge coordinators.
// Extracted from both bridge coordinators (WI-002) — zero logic change.
//
// Key decisions:
// - postSelectionNotification unifies single-TV and chunked versions via optional chunkOffset.
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

    /// Posts a selection notification with text and UTF-16 range.
    /// For chunked readers, pass `chunkOffset` to convert chunk-local to document-global.
    ///
    /// WI-7c5a: for `.readerSelectionPopoverRequested`, the wire
    /// format is a typed `SelectionPopoverRequestPayload` — this
    /// helper delegates to `SelectionPopoverRequest.post(...)` so
    /// that enum stays the single owner of the popover wire format.
    /// `requestToken` defaults to `nil` (TXT / MD / chunked never
    /// supply one — only EPUB's WI-7c5b producer does, and it does
    /// not route through this helper). For every other notification
    /// name the object remains a bare `TextSelectionInfo`.
    ///
    /// Feature #56 WI-12b: when `bilingualSegmentMap` is non-identity
    /// (bilingual interlinear is on), `range` is in the bridge's
    /// display-domain (the `UITextView`'s rendered text with synthetic
    /// translation runs); the helper maps it back to source-domain
    /// via `BilingualOffsetRouter.displayNSRange` so the posted
    /// `TextSelectionInfo` carries source offsets even when the user
    /// selects across or after a synthetic block. A selection whose
    /// start falls inside a synthetic run is dropped (no notification
    /// posted). Identity map = byte-identical pass-through.
    @MainActor
    static func postSelectionNotification(
        _ name: Notification.Name,
        from textView: UITextView,
        range: NSRange,
        chunkOffset: Int = 0,
        requestToken: UUID? = nil,
        bilingualSegmentMap: BilingualDisplaySegmentMap =
            BilingualDisplaySegmentMap.identity(sourceLength: 0)
    ) {
        guard range.location != NSNotFound,
              range.location >= 0,
              range.length >= 0 else { return }
        let text = textView.text ?? ""
        let nsText = text as NSString
        guard range.location <= nsText.length,
              range.length <= nsText.length - range.location else { return }
        let selectedText = nsText.substring(with: range)
        // Feature #56 WI-12b: route the display-domain range back to
        // source-domain when bilingual is on. Identity-map fast path
        // returns the input verbatim. A selection starting in a
        // synthetic run is dropped.
        let sourceRange: NSRange
        if bilingualSegmentMap.sourceLength == bilingualSegmentMap.displayLength {
            // Identity (off-mode) — no routing.
            sourceRange = range
        } else {
            // Bilingual on — map display range back to source range.
            // A selection start inside a synthetic run resolves to nil
            // and the notification is dropped.
            let startSource = bilingualSegmentMap.sourceOffset(
                forDisplayOffset: range.location
            )
            guard let start = startSource else { return }
            // The exclusive selection end at `range.location +
            // range.length` may legitimately land at a synthetic-block
            // start (the end-of-selection is the position AFTER the
            // last selected character). `sourceOffset(forDisplayOffset:)`
            // returns nil there; map it via the segment-union range
            // projection to handle boundary semantics correctly.
            let endSource: Int
            if range.length == 0 {
                endSource = start
            } else {
                let endDisplay = range.location + range.length
                if let e = bilingualSegmentMap.sourceOffset(forDisplayOffset: endDisplay) {
                    endSource = e
                } else {
                    // End fell into synthetic — use segment-union to
                    // project the selected display range back to source.
                    let projected = BilingualOffsetRouter.displayRange(
                        forSourceRange: 0..<bilingualSegmentMap.sourceLength,
                        map: bilingualSegmentMap
                    )
                    _ = projected
                    // Easier: find the segment containing `endDisplay - 1`,
                    // take its source upperBound.
                    let endProj = projectToSourceEnd(
                        displayOffset: endDisplay - 1, map: bilingualSegmentMap
                    )
                    endSource = max(start, endProj)
                }
            }
            sourceRange = NSRange(location: start, length: max(0, endSource - start))
        }
        let info = TextSelectionInfo(
            selectedText: selectedText,
            startUTF16: chunkOffset + sourceRange.location,
            endUTF16: chunkOffset + sourceRange.location + sourceRange.length
        )
        if name == .readerSelectionPopoverRequested {
            SelectionPopoverRequest.post(selection: info, requestToken: requestToken)
        } else {
            NotificationCenter.default.post(name: name, object: info)
        }
    }

    /// Feature #56 WI-12b: helper for the selection-end-at-synthetic
    /// boundary — find the source segment containing the display offset
    /// (or the nearest preceding one) and return its source upperBound.
    @MainActor
    private static func projectToSourceEnd(
        displayOffset: Int, map: BilingualDisplaySegmentMap
    ) -> Int {
        if let source = map.sourceOffset(forDisplayOffset: displayOffset) {
            return source + 1
        }
        var lastSourceEnd = 0
        for segment in map.segments {
            if case let .source(sourceRange, displayRange) = segment {
                if displayRange.lowerBound > displayOffset { break }
                lastSourceEnd = sourceRange.upperBound
            }
        }
        return lastSourceEnd
    }

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
