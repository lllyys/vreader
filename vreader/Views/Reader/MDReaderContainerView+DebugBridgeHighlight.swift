// Purpose: DEBUG-only wiring that creates an MD highlight from a
// `.debugBridgeHighlightCommand` notification (Bug #237 verification harness).
// Mirror of TXTReaderContainerView+DebugBridgeHighlight, scoped to MD only —
// see that file's header for the design rationale (format-host placement,
// LocatorFactory delegation, HighlightCoordinator.create atomicity).
//
// Entire file compiled out of Release builds via `#if DEBUG`.
//
// @coordinates-with MDReaderContainerView.swift,
//   DebugBridgeHighlightObserver.swift, LocatorFactory.swift,
//   HighlightCoordinator.swift, RealDebugBridgeContext.swift

import SwiftUI

#if !DEBUG
// Release stub: the body of MDReaderContainerView references
// `debugBridgeHighlightObserverModifier`; we provide an `EmptyModifier`
// here so Release builds compile without any DebugBridge symbols.
extension MDReaderContainerView {
    var debugBridgeHighlightObserverModifier: EmptyModifier {
        EmptyModifier()
    }
}
#endif

#if DEBUG

import OSLog

extension MDReaderContainerView {

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

    /// Handle a `.debugBridgeHighlightCommand` notification by creating an
    /// MD highlight at the given UTF-16 range over `viewModel.renderedText`.
    /// Goes through the host's `HighlightCoordinator.create(...)` so persist
    /// and paint are atomic (audit Round-1 Medium #3 fix).
    ///
    /// Format scoping (audit Round-1 High #2 fix): this observer is only
    /// attached inside MD hosts. EPUB / PDF / AZW3 don't see this
    /// notification because the modifier isn't applied there.
    @MainActor
    func handleDebugBridgeHighlightCommand(
        startUTF16: Int,
        endUTF16: Int,
        color: String?
    ) {
        let log = Logger(subsystem: "com.vreader.app", category: "DebugBridge")
        let myKey = viewModel.bookFingerprintKey

        log.info("md highlight observer: start=\(startUTF16) end=\(endUTF16) color=\(color ?? "nil", privacy: .public)")

        guard let fingerprint = DocumentFingerprint(canonicalKey: myKey) else {
            log.error("md highlight observer: bookFingerprintKey did not parse")
            return
        }

        let renderedText = viewModel.renderedText
        guard let locator = LocatorFactory.mdRange(
            fingerprint: fingerprint,
            charRangeStartUTF16: startUTF16,
            charRangeEndUTF16: endUTF16,
            sourceText: renderedText
        ) else {
            log.error(
                "md highlight observer: locator construction failed start=\(startUTF16) end=\(endUTF16)"
            )
            return
        }

        let selectedText = DebugBridgeHighlightObserver.extractSelectedText(
            locator: locator,
            continuousSource: renderedText,
            chapterSource: nil,
            chapterLocalStart: nil,
            chapterLocalEnd: nil
        )

        guard let coordinator = highlightCoordinator else {
            log.error("md highlight observer: highlightCoordinator not yet initialized")
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
                "md highlight observer: created start=\(startUTF16) end=\(endUTF16) color=\(resolvedColor, privacy: .public)"
            )
        }
    }
}

#endif
