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
import WebKit
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
    /// WI-8 (new-highlight): invoked with a finalized Readium text `Selection`
    /// when the user selects text, so the host can surface the designed
    /// `SelectionPopoverView` color picker and create a highlight. The coordinator
    /// binds this to its `shouldShowMenuForSelection` delegate callback.
    var onSelection: (@MainActor (ReadiumNavigator.Selection) -> Void)?
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
    /// WI-11b: the host-owned bilingual eval-channel sink the coordinator binds
    /// its production eval method into on `attach`, so the host's bilingual
    /// extension can drive enumerate/inject/clear on the live spine (same
    /// host → coordinator indirection as `navCommander`).
    let bilingualCommander: ReadiumBilingualCommander
    /// WI-7 photo/custom-background compositing: when true, the navigator
    /// container view is forced `.clear` (Readium's spine WebViews are already
    /// clear) so the `ThemeBackgroundView` composited behind the navigator in the
    /// host shows through. Paired with a NIL `EPUBPreferences.backgroundColor`
    /// (no `--USER__backgroundColor` body rule injected). Default `false` keeps
    /// the opaque theme-color path unchanged.
    var transparentBackground: Bool = false

    func makeCoordinator() -> ReadiumReaderCoordinator {
        ReadiumReaderCoordinator(
            fingerprintKey: fingerprintKey,
            readerToken: readerToken ?? UUID(),
            onLocationChange: onLocationChange,
            onSelection: onSelection,
            highlightAdapter: highlightAdapter,
            navCommander: navCommander,
            bilingualCommander: bilingualCommander
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
        // WI-7: set BEFORE the navigator builds so the coordinator's
        // `setupUserScripts` (called as each spine WebView loads) injects the
        // transparent-`:root` style for the photo/custom-bg path.
        context.coordinator.transparentBackground = transparentBackground
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
            // WI-7: make the navigator container transparent so a composited
            // ThemeBackgroundView shows through. Internal spine WebViews are
            // created lazily as spine items load, so `updateUIViewController`
            // re-applies as they appear.
            Self.applyTransparency(transparentBackground, to: navigator)
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
            // Gate-4 audit High: drive the transparency state through the
            // coordinator so a LIVE disable removes the injected style from
            // already-loaded spreads (not just future ones). No-ops when the flag
            // is unchanged.
            context.coordinator.setTransparentBackground(transparentBackground)
            // The pref re-submit (theme/font/scroll) must run before the
            // container-view re-paint, since `submitPreferences` itself re-paints
            // the navigator view to `effectiveBackgroundColor`.
            navigator.submitPreferences(preferences)
            // WI-7: re-apply container/WebView opacity. Spine WebViews mount
            // lazily as the reader paginates, and a Display-settings change can
            // rebuild this representable with a new `transparentBackground` value.
            Self.applyTransparency(transparentBackground, to: navigator)
        }
    }

    /// WI-7 photo/custom-background compositing. Readium's spine `WKWebView`s are
    /// already `.clear` (`EPUBSpreadView`), but the navigator CONTAINER view is
    /// painted `settings.effectiveBackgroundColor.uiColor` on every preference
    /// submit (`EPUBNavigatorViewController` `apply(settings:)`). When a nil
    /// `backgroundColor` pref is in play that swatch is the theme color, which
    /// would occlude the composited `ThemeBackgroundView` behind. SYMMETRIC
    /// (Gate-4 audit Medium): when transparent, force the container view `.clear`;
    /// when opaque, restore `effectiveBackgroundColor` (the value Readium just
    /// re-applied via `submitPreferences`) + `isOpaque = true`, so a live disable
    /// does not leave a stale-clear navigator over a now-removed background.
    @MainActor
    private static func applyTransparency(
        _ transparent: Bool,
        to navigator: EPUBNavigatorViewController
    ) {
        if transparent {
            navigator.view.backgroundColor = .clear
            navigator.view.isOpaque = false
        } else {
            // Readium's `submitPreferences` (called just before this) already set
            // the container view to `effectiveBackgroundColor`; only the
            // `isOpaque` flag could be stale-false from a prior transparent pass.
            navigator.view.isOpaque = true
        }
        applyWebViewOpacity(transparent, in: navigator.view)
    }

    @MainActor
    private static func applyWebViewOpacity(_ transparent: Bool, in view: UIView) {
        for subview in view.subviews {
            if let webView = subview as? WKWebView {
                // Readium owns the WebView background (`.clear` in `EPUBSpreadView`);
                // only re-assert the `isOpaque` flag so an opaque-path WebView is
                // not left flagged transparent after a live disable. Leave the
                // `backgroundColor` to Readium (the html/body CSS owns the paint).
                webView.isOpaque = !transparent
            }
            applyWebViewOpacity(transparent, in: subview)
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
