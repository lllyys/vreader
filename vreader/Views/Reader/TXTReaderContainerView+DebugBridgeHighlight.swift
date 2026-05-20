// Purpose: DEBUG-only wiring that creates a TXT highlight from a
// `.debugBridgeHighlightCommand` notification (Bug #237 verification harness).
// The observer lives inside the TXT format host (not the generic
// `ReaderContainerView`) so it has direct access to the source text,
// chapter index, and `HighlightCoordinator` the gesture path uses — the
// bridge-created highlight is byte-identical to a gesture-created one.
//
// Entire file compiled out of Release builds via `#if DEBUG`.
//
// Why the format-host placement (audit Round-1 High #1 / #2 fixes):
//   - `LocatorFactory.txtChapterRange` / `txtRange` extract textQuote +
//     textContextBefore + textContextAfter from the source text. Those
//     fields are part of `Locator.canonicalHash`, so a gesture-created
//     highlight and a bridge-created highlight at the same (start, end)
//     would NOT dedupe through the `profileKey` path in
//     `PersistenceActor.addHighlight` if either side omitted them.
//   - Going through the host's `HighlightCoordinator.create(...)` is the
//     same path the gesture wires through `ReaderNotificationModifier`'s
//     `.readerHighlightRequested` handler — persist + paint atomically,
//     no cancellation gap between the two.
//   - Format scoping: EPUB / PDF / AZW3 don't register this observer,
//     so the URL is silently a no-op for them (TXT-shaped highlight
//     persisted against an EPUB book would be invisible and contaminate
//     the library).
//
// @coordinates-with TXTReaderContainerView.swift,
//   DebugBridgeHighlightObserver.swift, LocatorFactory.swift,
//   HighlightCoordinator.swift, RealDebugBridgeContext.swift

import SwiftUI

#if !DEBUG
// Release stub: the body of TXTReaderContainerView references
// `debugBridgeHighlightObserverModifier`; we provide an `EmptyModifier`
// here so Release builds compile without any DebugBridge symbols.
extension TXTReaderContainerView {
    var debugBridgeHighlightObserverModifier: EmptyModifier {
        EmptyModifier()
    }
}
#endif

#if DEBUG

import OSLog

extension TXTReaderContainerView {

    /// The shared `DebugBridgeHighlightObserver` modifier wired to this
    /// host's `handleDebugBridgeHighlightCommand`. The view body's
    /// `.modifier(...)` chain reads this property unconditionally;
    /// outside `#if DEBUG` (i.e. Release) a parallel `EmptyModifier`
    /// stub of the same name keeps the body compiling without any
    /// DebugBridge symbols leaking.
    var debugBridgeHighlightObserverModifier: some ViewModifier {
        DebugBridgeHighlightObserver(
            onCommand: { startUTF16, endUTF16, color in
                handleDebugBridgeHighlightCommand(
                    startUTF16: startUTF16, endUTF16: endUTF16, color: color
                )
            }
        )
    }

    /// Handle a `.debugBridgeHighlightCommand` notification by creating a
    /// TXT highlight at the given UTF-16 range and triggering a re-paint
    /// through the same `HighlightCoordinator.create(...)` path the gesture
    /// uses. The bridge writes a TXT-shaped Locator with extracted
    /// textQuote + context so it is dedupe-compatible with gesture-created
    /// highlights at the same offsets.
    ///
    /// Range semantics (matching `LocatorFactory`):
    ///   - Continuous mode: `start`/`end` are document-global UTF-16 offsets
    ///     into `viewModel.textContent`. Delegates to `LocatorFactory.txtRange`.
    ///   - Chapter mode: `start`/`end` are chapter-LOCAL UTF-16 offsets
    ///     into `viewModel.currentChapterText`; translated to document-global
    ///     via the active chapter's `globalStartUTF16`. Delegates to
    ///     `LocatorFactory.txtChapterRange`.
    ///
    /// Format scoping (audit Round-1 High #2 fix): this observer is only
    /// attached inside TXT hosts. EPUB / PDF / AZW3 don't see this
    /// notification because the modifier isn't applied there.
    @MainActor
    func handleDebugBridgeHighlightCommand(
        startUTF16: Int,
        endUTF16: Int,
        color: String?
    ) {
        let log = Logger(subsystem: "com.vreader.app", category: "DebugBridge")
        let myKey = viewModel.bookFingerprintKey

        log.info(
            "txt highlight observer: start=\(startUTF16) end=\(endUTF16) color=\(color ?? "nil", privacy: .public) chapter=\(self.viewModel.isChapterMode) continuous=\(self.viewModel.isContinuousMode)"
        )

        // Resolve the canonical fingerprint. A malformed key here would
        // also break the gesture path, so we just log and bail.
        guard let fingerprint = DocumentFingerprint(canonicalKey: myKey) else {
            log.error("txt highlight observer: bookFingerprintKey did not parse")
            return
        }

        // Build the format-correct Locator using the same factory the
        // gesture path uses (see `TXTReaderContainerView.makeNotificationDeps`
        // and `TXTReaderContainerView.makeLocatorForTXT`).
        let locator: Locator?
        if viewModel.isContinuousMode {
            // Continuous mode: caller-supplied offsets are document-global.
            // `txtRange` extracts textQuote + context from `textContent`
            // when supplied — the canonical gesture-path posture.
            locator = LocatorFactory.txtRange(
                fingerprint: fingerprint,
                charRangeStartUTF16: startUTF16,
                charRangeEndUTF16: endUTF16,
                sourceText: viewModel.textContent
            )
        } else if viewModel.isChapterMode {
            // Chapter mode: caller-supplied offsets are chapter-local.
            // Translate to document-global via the active chapter's
            // `globalStartUTF16` (the helper `makeLocatorForTXT` already
            // encapsulates this and the local→global addition).
            let chapters = viewModel.chapterIndex?.chapters ?? []
            let idx = viewModel.currentChapterIdx
            let chapter = (idx >= 0 && idx < chapters.count) ? chapters[idx] : nil
            locator = TXTReaderContainerView.makeLocatorForTXT(
                fingerprint: fingerprint,
                localStart: startUTF16,
                localEnd: endUTF16,
                chapterText: viewModel.currentChapterText,
                chapterGlobalStart: chapter?.globalStartUTF16 ?? 0,
                isChapterMode: true
            )
        } else {
            // Neither mode active yet (loading / error state). Treat the
            // offsets as document-global so the URL still has a defined
            // behavior; the `viewModel.textContent` may be nil so context
            // extraction is skipped — that's the same posture as a
            // gesture before content loads.
            locator = LocatorFactory.txtRange(
                fingerprint: fingerprint,
                charRangeStartUTF16: startUTF16,
                charRangeEndUTF16: endUTF16,
                sourceText: viewModel.textContent
            )
        }
        guard let locator else {
            log.error(
                "txt highlight observer: locator construction failed start=\(startUTF16) end=\(endUTF16)"
            )
            return
        }

        // Extract the selected text from the same source the locator
        // factory used. Empty when no source text is available — matches
        // the gesture path's `LocatorFactory` posture (it gets `textQuote`
        // from the same source, so the selectedText here mirrors that).
        let selectedText = DebugBridgeHighlightObserver.extractSelectedText(
            locator: locator,
            continuousSource: viewModel.isContinuousMode ? viewModel.textContent : nil,
            chapterSource: viewModel.isChapterMode ? viewModel.currentChapterText : nil,
            chapterLocalStart: viewModel.isChapterMode ? startUTF16 : nil,
            chapterLocalEnd: viewModel.isChapterMode ? endUTF16 : nil
        )

        // Spawn the create through the host's HighlightCoordinator — same
        // path the gesture wires through `ReaderNotificationModifier`'s
        // `.readerHighlightRequested` handler. `create` persists THEN
        // paints atomically (audit Round-1 Medium #3 fix), so no
        // cancellation race between persistence and re-paint.
        guard let coordinator = highlightCoordinator else {
            log.error("txt highlight observer: highlightCoordinator not yet initialized")
            return
        }
        let resolvedColor = color ?? DebugBridgeHighlightObserver.defaultColor
        let noAnchor: AnnotationAnchor? = nil
        let noNote: String? = nil
        Task { @MainActor in
            _ = await coordinator.create(
                locator: locator,
                anchor: noAnchor,
                selectedText: selectedText,
                color: resolvedColor,
                note: noNote
            )
            log.info(
                "txt highlight observer: created start=\(startUTF16) end=\(endUTF16) color=\(resolvedColor, privacy: .public)"
            )
        }
    }
}

#endif
