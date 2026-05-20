// Purpose: Side-tap → page-turn dispatcher for the native reader bridges.
//
// Background: Bug #239 (regression of features #21 / #25). Feature #54 WI-3
// (commit e30f769) deleted `ReaderUnifiedDispatch.swift`, the only mount of
// the legacy `.tapZoneOverlay(config:)` modifier. `TapZoneDispatcher` had been
// the sole producer of `.readerNextPage` / `.readerPreviousPage` app-wide; once
// it was unmounted, every native reader container's `onReceive(.readerNextPage)`
// observer went dead and side-tap page-turn stopped working in Paged layout
// across all five native readers (TXT / MD / EPUB / AZW3 / PDF).
//
// This file restores the producer — without re-introducing the deleted SwiftUI
// overlay, which used to swallow scroll gestures on UIKit-backed renderers
// (bug #70). Instead, each native bridge already owns its own tap handler;
// `ReaderTapZoneRouter` is the small pure helper they call to translate a tap
// at (x, totalWidth) into a `.readerNextPage` / `.readerPreviousPage` /
// `.readerContentTapped` notification — the very notifications the containers
// already observe.
//
// Design source: dev-docs/designs/vreader-fidelity-v1/project/design-notes/reader-navigation.md
// §1 (30/40/30 zone grammar carried over from `vreader-reader.jsx::handleTap`)
// and §2.2 (side-tap in paged mode). The Swift `TapZoneConfig.zone(atX:totalWidth:)`
// helper that this router delegates to splits the screen into thirds — kept as
// the canonical zone classifier rather than re-imposing 30/40/30 to avoid
// breaking the existing `TapZoneTests` table; the difference is one-pixel-class
// at the boundaries and the bug #239 user-visible repro is satisfied by either
// split.
//
// Key decisions:
// - Layout-gated: ONLY in `.paged` layout do the left/right zones produce
//   page-turn notifications. In `.scroll` (and `nil`) every tap collapses to
//   `.readerContentTapped` — the legacy chrome-toggle behavior. This matches
//   the reader-navigation design (paged mode = discrete-page grammar; scroll
//   mode = continuous flow, no chapter walls).
// - Action lookup honors a caller-supplied `TapZoneConfig` (defaults to the
//   feature-#25 default mapping: left=prev, center=toggle, right=next), so the
//   legacy customization contract is preserved.
// - Pure `action(...)` separated from the side-effecting `dispatch(...)` so
//   unit tests can exercise the routing decision without a notification
//   round-trip (the dispatch overload covers the wiring path).
//
// @coordinates-with: TapZoneConfig.swift, ReaderNotifications.swift,
//                    EPUBLayoutPreference.swift, TapZoneOverlay.swift
//                    (kept dormant for legacy compat — its TapZoneDispatcher
//                    contract is what this router reproduces; the modifier
//                    itself is never re-mounted on native readers).

import Foundation
import SwiftUI

/// Pure helper + dispatcher that turns a tap at (x, totalWidth) into a
/// `TapAction` and, optionally, the matching `NotificationCenter` post.
///
/// Native reader bridges (TXT / MD / EPUB / AZW3 / PDF) call `dispatch(...)`
/// from their existing UIKit tap handler / WKWebView JS bridge after the
/// per-bridge pre-checks (highlight hit-test, link clicks, link-suppress
/// regions, etc.) have not claimed the tap.
enum ReaderTapZoneRouter {

    /// Resolves a tap at `x` on a surface of width `totalWidth` to a
    /// `TapAction`, gated by the layout preference.
    ///
    /// - In `.paged` layout, the zone the tap falls in (per
    ///   `TapZoneConfig.zone(atX:totalWidth:)`) maps to the action defined
    ///   by `config` — by default left → previousPage, center → toggleChrome,
    ///   right → nextPage.
    /// - In `.scroll` layout (or when `layout` is nil), every tap returns
    ///   `.toggleChrome`. Page-turn is paged-mode-only.
    static func action(
        x: CGFloat,
        totalWidth: CGFloat,
        layout: EPUBLayoutPreference?,
        config: TapZoneConfig = .default
    ) -> TapAction {
        guard layout == .paged else { return .toggleChrome }
        let zone = TapZoneConfig.zone(atX: x, totalWidth: totalWidth)
        return config.action(for: zone)
    }

    /// Dispatches the resolved action over `NotificationCenter`, posting one
    /// of:
    /// - `.readerNextPage` — paged-mode right-zone tap.
    /// - `.readerPreviousPage` — paged-mode left-zone tap.
    /// - `.readerContentTapped` — center-zone tap, or any tap outside paged
    ///   layout. Native reader containers observe this notification to toggle
    ///   their chrome.
    /// - nothing — when the resolved action is `.none` (legacy feature-#25
    ///   configurability allows a user to deliberately mute a zone).
    ///
    /// Same notification contract as the legacy `TapZoneDispatcher.dispatch`.
    static func dispatch(
        x: CGFloat,
        totalWidth: CGFloat,
        layout: EPUBLayoutPreference?,
        config: TapZoneConfig = .default
    ) {
        let resolved = action(
            x: x, totalWidth: totalWidth, layout: layout, config: config
        )
        switch resolved {
        case .previousPage:
            NotificationCenter.default.post(name: .readerPreviousPage, object: nil)
        case .nextPage:
            NotificationCenter.default.post(name: .readerNextPage, object: nil)
        case .toggleChrome:
            NotificationCenter.default.post(name: .readerContentTapped, object: nil)
        case .none:
            break
        }
    }
}
