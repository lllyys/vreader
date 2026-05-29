// Purpose: Feature #42 — `UIViewControllerRepresentable` bridging the Readium
// `EPUBNavigatorViewController` into SwiftUI for `ReadiumEPUBHost`. Builds the
// navigator once the publication is open, wires the coordinator (delegate +
// highlight adapter + nav commander), and tears down on dismantle. Extracted
// from `ReadiumEPUBHost.swift` (Gate-4 WI-9a: file-size split).
//
// @coordinates-with ReadiumEPUBHost.swift, ReadiumReaderCoordinator.swift,
//   ReadiumDecorationHighlightAdapter.swift

#if canImport(UIKit)
import SwiftUI
import UIKit
import ReadiumShared
import ReadiumNavigator

struct ReadiumNavigatorRepresentable: UIViewControllerRepresentable {
    let publication: Publication
    let preferences: EPUBPreferences
    let fingerprintKey: String
    let readerToken: UUID?
    /// WI-6: the restored reading position to open at, or nil to open at the
    /// start. Passed straight into `EPUBNavigatorViewController(initialLocation:)`.
    let initialLocation: ReadiumShared.Locator?
    /// Med-2: invoked (on the main actor, deferred past the current render
    /// pass) when `EPUBNavigatorViewController` init throws, so the host can
    /// flip to `.failed`. `@MainActor @Sendable` so capturing it into the
    /// deferral `Task` is clean under `SWIFT_STRICT_CONCURRENCY = complete`
    /// (Gate-4 round-2 Med).
    var onNavigatorInitFailure: (@MainActor @Sendable (String) -> Void)?
    /// WI-6: invoked with the navigator's reported locator on every
    /// `locationDidChange`, so the host's VM can debounce-save the position.
    /// `@MainActor @Sendable` so the coordinator can hold it across the
    /// navigator-delegate boundary under strict concurrency.
    var onLocationChange: (@MainActor @Sendable (ReadiumShared.Locator) -> Void)?
    /// WI-8: the host-owned highlight adapter, bound to the navigator in
    /// `makeUIViewController` and released in `dismantleUIViewController`. The
    /// adapter is a `DecorableNavigator` client; the host's `HighlightCoordinator`
    /// drives its restore / apply / remove.
    let highlightAdapter: ReadiumDecorationHighlightAdapter
    /// WI-9a: the host-owned navigation sink the coordinator binds its nav
    /// methods into on `attach`, so the host's page-turn / jump observers reach
    /// the live navigator (host → coordinator indirection, mirror of WI-8's
    /// host-owned-adapter wiring).
    let navCommander: ReadiumNavCommander

    func makeCoordinator() -> ReadiumReaderCoordinator {
        ReadiumReaderCoordinator(
            fingerprintKey: fingerprintKey,
            readerToken: readerToken ?? UUID(),
            onLocationChange: onLocationChange,
            highlightAdapter: highlightAdapter,
            navCommander: navCommander
        )
    }

    /// WI-9a: the layout the coordinator's tap-router needs, derived from the
    /// preferences' `scroll` flag (the host computes `preferences` from
    /// `ReaderSettingsStore.epubLayout`, so this round-trips the enum without
    /// threading it separately).
    private var resolvedLayout: EPUBLayoutPreference {
        preferences.scroll == true ? .scroll : .paged
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let config = EPUBNavigatorViewController.Configuration(preferences: preferences)
        do {
            let navigator = try EPUBNavigatorViewController(
                publication: publication,
                initialLocation: initialLocation,
                config: config
            )
            navigator.delegate = context.coordinator
            // WI-9a: tell the coordinator the current layout so `didTapAt`
            // routes side-taps to page-turns only in `.paged` mode.
            context.coordinator.currentLayout = resolvedLayout
            context.coordinator.attach(navigator: navigator)
            // WI-8: bind the highlight adapter to the same navigator + the
            // publication's spine hrefs so stored decorations render on the live
            // spine. The spine hrefs let the adapter resolve a LEGACY stored href
            // (`chapter1.xhtml`) to Readium's container-relative form
            // (`OEBPS/chapter1.xhtml`) — without it Readium can't route the
            // decoration and it silently doesn't render (the migration
            // href-mismatch). The adapter already holds the restored set (the
            // host's coordinator called `restoreAll()` before the navigator
            // mounted), so `attach` re-submits it with resolved hrefs.
            highlightAdapter.attach(
                navigator: navigator,
                spineHrefs: publication.readingOrder.map(\.href)
            )
            return navigator
        } catch {
            context.coordinator.log.error(
                "ReadiumEPUB navigator init failed: \(String(describing: error), privacy: .public)"
            )
            // Med-2: a representable must return a controller synchronously, so
            // hand back an empty placeholder and route the failure into host
            // state on the next main-actor turn (mutating @State synchronously
            // here would be a "modifying state during view update" violation).
            // The host then swaps this placeholder for its `.failed` error view.
            let handler = onNavigatorInitFailure
            let message = String(describing: error)
            Task { @MainActor in handler?(message) }
            return UIViewController()
        }
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        // WI-7: the host body reads `settingsStore.theme` + `.typography` +
        // `.epubLayout` and recomputes `preferences` on every Display-settings
        // change, so this re-submit applies the new theme/font/line-height/scroll
        // to the live navigator without a reopen.
        // WI-9a: keep the coordinator's layout in sync so a live scroll↔paged
        // switch re-routes the tap behavior immediately.
        context.coordinator.currentLayout = resolvedLayout
        if let navigator = controller as? EPUBNavigatorViewController {
            navigator.submitPreferences(preferences)
        }
    }

    /// High (bug #252 lesson): deterministic navigator + registry teardown when
    /// the representable leaves the hierarchy. The coordinator knows its own
    /// `(fingerprintKey, token)` — which the host cannot when `readerToken` was
    /// nil and the coordinator generated its own — so it owns the clear.
    static func dismantleUIViewController(
        _ controller: UIViewController,
        coordinator: ReadiumReaderCoordinator
    ) {
        coordinator.detach()
    }
}

/// Navigator-delegate + DebugBridge coordinator for the Readium EPUB host.
/// `final class` (not the SwiftUI view) so it survives view-body recomputation
/// and can hold the navigator + per-reader token. `@MainActor` because the
/// navigator and its WebViews are main-actor-isolated (feature #42 Med-4).

#endif
