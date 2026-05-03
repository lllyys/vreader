// Purpose: UIApplicationDelegate adapter that captures the
// `handleEventsForBackgroundURLSession` completion handler so the
// LazyDownloadCoordinator can invoke it from
// `urlSessionDidFinishEvents(forBackgroundURLSession:)`. iOS will
// suspend the app's background-launch grace period until the handler
// runs, so dropping it leaks battery and orphans pending events.
//
// SwiftUI's `App` lifecycle doesn't expose this hook, so we bridge it
// via `@UIApplicationDelegateAdaptor(VReaderAppDelegate.self)` in
// `VReaderApp`.
//
// Feature #47 WI-3b.
//
// @coordinates-with: VReaderApp.swift, LazyDownloadCoordinator.swift,
//   LazyDownloadDelegate.swift,
//   dev-docs/plans/20260503-feature-47-selective-picker-lazy-load.md

import UIKit
import OSLog

private let log = Logger(subsystem: "com.vreader.app", category: "VReaderAppDelegate")

final class VReaderAppDelegate: NSObject, UIApplicationDelegate {

    /// Background-event completion handlers keyed by URLSession identifier.
    /// MainActor-isolated because reads/writes happen from the
    /// UIApplicationDelegate callback (UIKit guarantees main thread) and
    /// the LazyDownloadCoordinator (`@MainActor`). Static so the
    /// coordinator can retrieve handlers without holding a reference to
    /// the adapter instance — `@UIApplicationDelegateAdaptor` doesn't
    /// expose its instance through SwiftUI Environment.
    @MainActor
    static var backgroundCompletionHandlers: [String: () -> Void] = [:]

    /// iOS calls this on the main thread when relaunching the app to
    /// deliver background download events. Stores the handler
    /// synchronously — an async hop here can race
    /// `urlSessionDidFinishEvents` and lose the handler, leaking iOS's
    /// background-launch grace period.
    func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        MainActor.assumeIsolated {
            Self.storeBackgroundHandler(completionHandler, for: identifier)
        }
    }

    /// Stores a completion handler for `identifier`. If a handler for the
    /// same identifier is already present (rare — would mean iOS
    /// delivered a second handoff for the same session events without
    /// the previous one being released), invokes the old handler before
    /// replacing it so the previous run doesn't leak the grace period.
    @MainActor
    static func storeBackgroundHandler(_ handler: @escaping () -> Void, for identifier: String) {
        if let previous = backgroundCompletionHandlers[identifier] {
            log.error(
                "duplicate handleEventsForBackgroundURLSession for \(identifier, privacy: .public); invoking previous handler before replace"
            )
            previous()
        }
        backgroundCompletionHandlers[identifier] = handler
    }

    /// Removes and returns the handler for the given identifier. Called
    /// by `LazyDownloadCoordinator.didFinishBackgroundEvents` from the
    /// `URLSessionDelegate.urlSessionDidFinishEvents` hop. Returns nil
    /// if no handler was registered (events arrived without a fresh
    /// app launch — normal during foreground operation).
    @MainActor
    static func takeBackgroundHandler(for identifier: String) -> (() -> Void)? {
        backgroundCompletionHandlers.removeValue(forKey: identifier)
    }
}
