// Purpose: `locate` command handler for the vreader-debug:// scheme (feature
// #74 — CU-free locate-bloom verification harness). The locate "bloom" is a
// ~1.5s sub-second wash-lift that cannot be screenshot/video-captured on the
// Screen-Sharing virtual display, so this command drives the bloom through the
// REAL render path and the DEBUG snapshot reads it back
// (`landingBloomCount` / `landingBloomPeakIntensity`).
//
// The handler resolves the active book's fingerprintKey from the reader
// registry, fetches its persisted highlights (the SAME order the annotations
// sheet shows — newest first), picks the `highlightIndex`-th, and posts that
// highlight's saved `Locator` on `.readerNavigateToLocator` — the SAME channel
// a Notes/Highlights row tap uses. The TXT/MD container's handler then sets
// `uiState.highlightRange` + bumps `highlightNonce`, which fires the bloom.
// No-op when no reader is active or no Nth highlight exists (mirrors
// `navigate` / `seek` / `present`). DEBUG-only — entire file compiled out of
// Release.
//
// Split from RealDebugBridgeContext.swift for the 300-line LOC guideline
// (mirrors RealDebugBridgeContext+Navigate.swift).
//
// @coordinates-with: DebugBridge.swift, DebugCommand.swift,
//   DebugReaderRegistry.swift, PersistenceActor+Highlights.swift,
//   ReaderNotificationModifier.swift (the .readerNavigateToLocator observer),
//   ReaderNotifications.swift, RealDebugBridgeContextTests.swift

#if DEBUG

import Foundation

extension RealDebugBridgeContext {

    /// Feature #74 — drive `.readerNavigateToLocator` for the active TXT/MD
    /// reader so the locate bloom fires through the real render path.
    ///
    /// Resolves the active book's fingerprintKey from
    /// `DebugReaderRegistry.shared.current`, fetches its persisted highlights
    /// (newest-first, the same order the annotations sheet shows), and posts the
    /// `highlightIndex`-th highlight's saved `Locator` on
    /// `.readerNavigateToLocator` — exactly what a Notes/Highlights row tap
    /// does. If no reader is active, or `highlightIndex` is out of range for the
    /// book's highlights, the URL is silently a no-op (the same posture as
    /// `navigate` / `seek` / `present`).
    func locate(highlightIndex: Int) async throws {
        guard let fingerprintKey = DebugReaderRegistry.shared.current?.fingerprintKey else {
            log.info("locate: no active reader — no-op")
            return
        }
        let highlights = try await persistence.fetchHighlights(forBookWithKey: fingerprintKey)
        guard highlightIndex >= 0, highlightIndex < highlights.count else {
            log.info(
                "locate: index \(highlightIndex) out of range (\(highlights.count) highlight(s)) — no-op"
            )
            return
        }
        let locator = highlights[highlightIndex].locator
        NotificationCenter.default.post(
            name: .readerNavigateToLocator,
            object: locator
        )
        log.info(
            "locate: posted readerNavigateToLocator for highlight index \(highlightIndex) of \(highlights.count)"
        )
    }
}

#endif
