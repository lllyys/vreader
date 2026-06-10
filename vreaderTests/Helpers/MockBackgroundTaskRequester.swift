// Purpose: Feature #98 — shared recorder double for the
// `BackgroundTaskRequesting` seam. Records begin/end pairing, hands out
// monotonic identifiers, can deny requests (`.invalid`, the iOS
// no-background-time case), and captures each expiration handler so tests
// can fire OS expiry deterministically.
//
// @coordinates-with: BackgroundExecutionToken.swift,
//   ChapterReTranslateViewModel.swift, BookTranslationCoordinator.swift

import Foundation
import UIKit
@testable import vreader

@MainActor
final class MockBackgroundTaskRequester: BackgroundTaskRequesting {
    private(set) var begins: [String] = []
    private(set) var ends: [UIBackgroundTaskIdentifier] = []
    /// When true, every begin returns `.invalid` (iOS denied background time).
    var denyRequests = false
    /// Captured expiration handlers, keyed by the raw identifier returned
    /// from the matching begin (1-based, in begin order).
    private(set) var expiryHandlers: [Int: @MainActor () -> Void] = [:]

    func beginTask(
        name: String,
        expirationHandler: @escaping @MainActor () -> Void
    ) -> UIBackgroundTaskIdentifier {
        begins.append(name)
        if denyRequests { return .invalid }
        let raw = begins.count
        expiryHandlers[raw] = expirationHandler
        return UIBackgroundTaskIdentifier(rawValue: raw)
    }

    func endTask(_ identifier: UIBackgroundTaskIdentifier) {
        ends.append(identifier)
    }

    /// Fires the OS expiration handler captured for the `rawIdentifier`-th
    /// begin — the deterministic stand-in for iOS expiring the task.
    func fireExpiry(rawIdentifier: Int) {
        expiryHandlers[rawIdentifier]?()
    }
}
