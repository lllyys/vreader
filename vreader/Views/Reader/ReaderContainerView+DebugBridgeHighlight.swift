// Purpose: DEBUG-only wiring that creates a highlight from the
// `.debugBridgeHighlightCommand` notification (Bug #237 verification harness).
// The observer in ReaderContainerView calls this helper; this file owns the
// build-Locator → persist → re-paint orchestration so the host stays
// trivial.
//
// Entire file compiled out of Release builds via `#if DEBUG`.
//
// Why this bypasses the gesture: XCUITest cannot synthesize the long-press →
// text-selection → SelectionPopoverView color-tap sequence reliably on iOS 26
// (Bug #237 cause analysis). This DebugBridge command lets verification tests
// reach the same persistence + render outcome through a deterministic URL.
//
// Format scope: v1 supports TXT and MD only — they share UTF-16 offset
// coordinates on `Locator`. EPUB/PDF would need href+CFI or page; that's
// a follow-up if/when those features need it.
//
// @coordinates-with ReaderContainerView.swift, RealDebugBridgeContext.swift,
//   DebugBridgeNotifications.swift, PersistenceActor+Highlights.swift,
//   Locator.swift

#if DEBUG

import SwiftUI
import SwiftData
import OSLog

/// Dedicated `ViewModifier` for the Bug #237 highlight-driver observer.
/// Mirrors the `ReaderDebugBridgeSearchObserver` pattern — extracting the
/// `.onReceive` keeps the SwiftUI body inside the type-inference budget.
struct ReaderDebugBridgeHighlightObserver: ViewModifier {
    let onCommand: (_ startUTF16: Int, _ endUTF16: Int, _ color: String?) -> Void

    func body(content: Content) -> some View {
        content.onReceive(
            NotificationCenter.default.publisher(for: .debugBridgeHighlightCommand)
        ) { notification in
            guard let start = notification.userInfo?["start"] as? Int,
                  let end = notification.userInfo?["end"] as? Int else { return }
            let color = notification.userInfo?["color"] as? String
            onCommand(start, end, color)
        }
    }
}

extension ReaderContainerView {

    /// Handle a `.debugBridgeHighlightCommand` notification by creating a
    /// highlight at the given UTF-16 range and triggering a re-paint.
    ///
    /// Flow:
    ///   1. Resolve `book.fingerprintKey` → `DocumentFingerprint`.
    ///   2. Build a TXT/MD `Locator` with `charOffsetUTF16` /
    ///      `charRangeStartUTF16` / `charRangeEndUTF16`.
    ///   3. Call `PersistenceActor.addHighlight(...)` (the same actor method
    ///      the production gesture path uses).
    ///   4. Post `.readerHighlightsDidImport` so the per-format renderer
    ///      (TXT/MD) re-paints via `HighlightCoordinator.restoreAll`.
    ///
    /// Serialization: only one bridge-highlight task at a time. A new URL
    /// cancels the previous in-flight task. `.onDisappear` also cancels so
    /// late completion can't fire after the reader closed (mirror of the
    /// `+DebugBridgeSearch` posture).
    ///
    /// No-op when the URL fires with no reader presented — `.onReceive`
    /// only delivers to a mounted view, so callers see the same posture as
    /// `tts` / `search` (the URL succeeds; the live view applies it if
    /// present).
    ///
    /// Errors are surfaced as `log.error` entries; the URL still completes
    /// successfully from the bridge's perspective so its `lastError`
    /// stays clean (consistent with `tts` / `search`).
    @MainActor
    func handleDebugBridgeHighlightCommand(
        startUTF16: Int,
        endUTF16: Int,
        color: String?
    ) {
        let log = Logger(subsystem: "com.vreader.app", category: "DebugBridge")
        log.info(
            "highlight observer: received start=\(startUTF16) end=\(endUTF16) color=\(color ?? "nil", privacy: .public)"
        )

        // Cancel any prior in-flight bridge-highlight task. Two URLs in
        // rapid succession should produce two highlights (one per URL) in
        // order, but if the first hasn't finished and a second arrives,
        // we serialize via cancel-and-retry the same way the search
        // observer does.
        debugBridgeHighlightTask?.cancel()

        // Snapshot dependencies into local values so the Task doesn't
        // capture `self` directly across awaits.
        let key = book.fingerprintKey
        guard let fingerprint = DocumentFingerprint(canonicalKey: key) else {
            log.error("highlight observer: book.fingerprintKey did not parse as a DocumentFingerprint")
            return
        }
        let container = modelContext.container
        let resolvedColor = color ?? Self.defaultHighlightColor

        let task = Task { @MainActor in
            // Step 1: build a TXT/MD Locator. UTF-16 range fields populate
            // both `charOffsetUTF16` (the anchor offset, set to start) and
            // `charRangeStartUTF16` / `charRangeEndUTF16` (the range). This
            // mirrors how `LocatorFactory` builds locators on the production
            // gesture path — verify by grepping callers of
            // `Locator.validated(... charOffsetUTF16: ... charRangeStart...:
            // ... charRangeEnd...:)`.
            guard let locator = Locator.validated(
                bookFingerprint: fingerprint,
                charOffsetUTF16: startUTF16,
                charRangeStartUTF16: startUTF16,
                charRangeEndUTF16: endUTF16
            ) else {
                log.error(
                    "highlight observer: Locator validation rejected start=\(startUTF16) end=\(endUTF16)"
                )
                return
            }

            // Step 2: persist via the same actor method the gesture path
            // calls (HighlightCoordinator.create → PersistenceActor.addHighlight).
            // We can't re-use HighlightCoordinator here because it's owned
            // by individual format hosts (TXT/MD/EPUB), so we go through
            // PersistenceActor directly and rely on `.readerHighlightsDidImport`
            // to trigger re-paint in the active host.
            //
            // `selectedText` is intentionally left empty — the harness has
            // the range, not the selected text. Search/snapshot/export
            // can re-derive the text from the offsets if needed; the
            // renderer paints by range, not by text.
            let persistence = PersistenceActor(modelContainer: container)
            let record: HighlightRecord
            do {
                record = try await persistence.addHighlight(
                    locator: locator,
                    anchor: nil,
                    selectedText: "",
                    color: resolvedColor,
                    note: nil,
                    toBookWithKey: key
                )
            } catch {
                log.error("highlight observer: persistence.addHighlight threw \(String(describing: error), privacy: .public)")
                return
            }

            guard !Task.isCancelled else {
                log.info("highlight observer: cancelled after persistence, skipping re-paint")
                return
            }

            // Step 3: post `.readerHighlightsDidImport` so the per-format
            // renderer (TXT/MD/EPUB/PDF) re-fetches and repaints. This is
            // the same notification the annotations import flow uses, so
            // every host already handles it.
            NotificationCenter.default.post(name: .readerHighlightsDidImport, object: nil)
            log.info(
                "highlight observer: persisted id=\(record.highlightId.uuidString, privacy: .public) color=\(resolvedColor, privacy: .public)"
            )
        }
        debugBridgeHighlightTask = task
    }

    /// Default highlight color when the URL omits `color=`. Matches the
    /// production gesture path's fallback (`resolveHighlightColor` in
    /// `ReaderNotificationModifier.swift`).
    static let defaultHighlightColor = "yellow"
}

#endif
