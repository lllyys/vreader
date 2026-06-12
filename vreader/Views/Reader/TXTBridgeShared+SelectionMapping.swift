// Purpose: TXTBridgeShared's selection-notification routing — posts the
// selection notifications (popover/highlight/annotation/define/translate)
// with display→source bilingual offset mapping (feature #56 WI-12b) and
// the bug-#350 synthetic-start projection. Split from TXTBridgeShared.swift
// to keep both under the ~300-line guideline.
//
// Key decisions:
// - postSelectionNotification unifies single-TV and chunked versions via
//   optional chunkOffset.
// - A selection STARTING in a synthetic translation row is projected to
//   the source domain (bug #350), not dropped: inside-row anchors to the
//   parent paragraph; spanning-out starts at the following source segment.
//
// @coordinates-with TXTBridgeShared.swift, TXTTextViewBridge.swift,
//   TXTChunkedReaderBridge.swift, SelectionCardFallback.swift,
//   BilingualDisplaySegmentMap.swift, ReaderNotifications.swift

import UIKit

extension TXTBridgeShared {

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
    /// selects across or after a synthetic block. Identity map =
    /// byte-identical pass-through.
    ///
    /// Bug #350: a selection whose start falls inside a synthetic
    /// (translation-row) run is PROJECTED, not dropped — entirely
    /// inside one row anchors to the parent (nearest preceding) source
    /// paragraph's full range; spanning out of the row starts at the
    /// following source segment. Only a synthetic run with no
    /// preceding source paragraph (nothing to anchor) still drops.
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
        // Feature #56 WI-12b: route the display-domain range back to
        // source-domain when bilingual is on. Identity-map fast path
        // returns the input verbatim.
        if bilingualSegmentMap.sourceLength == bilingualSegmentMap.displayLength {
            // Identity (off-mode) — no routing.
            postInfo(
                name, selectedText: nsText.substring(with: range),
                sourceRange: range, chunkOffset: chunkOffset,
                requestToken: requestToken
            )
            return
        }
        // Bilingual on — map display range back to source range, then
        // rebuild the text from that FINAL source span. Codex rounds 2+3
        // (Medium): offsets and text must describe the same span on EVERY
        // bilingual path — a selection that starts in or spans across a
        // synthetic translation row must never post translation text with
        // source offsets (it would leak mismatched quotes into the
        // highlight/note/define/translate flows).
        guard let sourceRange = mapDisplayToSource(
            range: range, map: bilingualSegmentMap
        ) else { return }
        let sourceText = displayText(
            forSourceRange: sourceRange.location
                ..< (sourceRange.location + sourceRange.length),
            map: bilingualSegmentMap,
            displayText: nsText
        )
        postInfo(
            name, selectedText: sourceText, sourceRange: sourceRange,
            chunkOffset: chunkOffset, requestToken: requestToken
        )
    }

    /// Maps a display-domain selection to its source-domain span.
    /// Returns `nil` only when there is nothing to anchor to (a selection
    /// inside a synthetic run with no preceding source segment).
    @MainActor
    private static func mapDisplayToSource(
        range: NSRange, map: BilingualDisplaySegmentMap
    ) -> NSRange? {
        guard let start = map.sourceOffset(forDisplayOffset: range.location) else {
            // Bug #350: start inside a synthetic (translation) run —
            // project to the source domain instead of silently dropping.
            return projectSyntheticStartSelection(displayRange: range, map: map)
        }
        // The exclusive selection end at `range.location + range.length`
        // may legitimately land at a synthetic-block start (the
        // end-of-selection is the position AFTER the last selected
        // character). `sourceOffset(forDisplayOffset:)` returns nil
        // there; project it to the last source segment's upperBound.
        let endSource: Int
        if range.length == 0 {
            endSource = start
        } else {
            let endDisplay = range.location + range.length
            if let e = map.sourceOffset(forDisplayOffset: endDisplay) {
                endSource = e
            } else {
                // End fell into synthetic — find the segment containing
                // `endDisplay - 1`, take its source upperBound.
                let endProj = projectToSourceEnd(
                    displayOffset: endDisplay - 1, map: map
                )
                endSource = max(start, endProj)
            }
        }
        return NSRange(location: start, length: max(0, endSource - start))
    }

    /// Shared notification tail — builds the `TextSelectionInfo` from a
    /// source-domain range and posts on the right wire format.
    @MainActor
    private static func postInfo(
        _ name: Notification.Name,
        selectedText: String,
        sourceRange: NSRange,
        chunkOffset: Int,
        requestToken: UUID?
    ) {
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

    /// Bug #350: projects a selection that STARTS inside a synthetic
    /// (translation-row) run back to the source domain.
    ///
    /// - Selection spanning OUT of the row into following source text →
    ///   starts at the following source segment's `sourceRange.lowerBound`,
    ///   ends via the shared end-projection.
    /// - Selection entirely inside one row → anchors to the parent
    ///   (nearest preceding) source paragraph's FULL range, so the card
    ///   raises with the paragraph the translation belongs to.
    /// - No preceding source segment (synthetic-first edge) → `nil`
    ///   (caller drops — nothing to anchor to).
    @MainActor
    private static func projectSyntheticStartSelection(
        displayRange: NSRange, map: BilingualDisplaySegmentMap
    ) -> NSRange? {
        let endDisplay = displayRange.location + displayRange.length
        var precedingSource: Range<Int>?
        var followingSource: (source: Range<Int>, display: Range<Int>)?
        for segment in map.segments {
            if case let .source(sourceRange, segDisplay) = segment {
                if segDisplay.upperBound <= displayRange.location {
                    precedingSource = sourceRange
                } else if segDisplay.lowerBound >= displayRange.location,
                          followingSource == nil {
                    followingSource = (sourceRange, segDisplay)
                }
            }
        }
        if let following = followingSource,
           following.display.lowerBound < endDisplay {
            // Spans out of the translation row into real source text.
            let start = following.source.lowerBound
            let end = max(
                start,
                projectToSourceEnd(displayOffset: endDisplay - 1, map: map)
            )
            return NSRange(location: start, length: end - start)
        }
        guard let parent = precedingSource else { return nil }
        return NSRange(location: parent.lowerBound, length: parent.count)
    }

    /// Codex round 2 (Medium): extracts the text a SOURCE range refers
    /// to from the display string. `.source` segments render the source
    /// text verbatim (1:1 UTF-16 within a segment), so each overlap maps
    /// linearly back to a display slice; synthetic runs between source
    /// segments are skipped (they're not part of the source span).
    @MainActor
    private static func displayText(
        forSourceRange src: Range<Int>,
        map: BilingualDisplaySegmentMap,
        displayText: NSString
    ) -> String {
        var out = ""
        for segment in map.segments {
            if case let .source(sourceRange, displayRange) = segment {
                let lo = max(src.lowerBound, sourceRange.lowerBound)
                let hi = min(src.upperBound, sourceRange.upperBound)
                guard lo < hi else { continue }
                let dLo = displayRange.lowerBound + (lo - sourceRange.lowerBound)
                let len = hi - lo
                guard dLo >= 0, dLo + len <= displayText.length else { continue }
                out += displayText.substring(with: NSRange(location: dLo, length: len))
            }
        }
        return out
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
}
