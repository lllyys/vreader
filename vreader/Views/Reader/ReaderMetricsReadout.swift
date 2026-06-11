// Purpose: Feature #101 — the pure page↔time metrics-readout cycle seam.
// All cycle rules live here (Gate-2 M4) so the SwiftUI chrome layer stays
// wiring: which readout renders, when a tap cycles, and how the persisted
// per-book choice resolves.
//
// @coordinates-with: ReaderBottomChrome.swift, PerBookSettings.swift,
//   dev-docs/plans/20260611-feature-101-reading-time.md

import Foundation

/// Which readout the bottom-chrome trailing label shows.
enum ReaderMetricsReadout: String, Sendable, Equatable {
    /// The format's page-ish readout ("414 pages left in book",
    /// "Chapter 8 of 54", a percent) — the default.
    case pages
    /// The combined time readout ("12m read · 6h 40m total").
    case time

    /// Resolves the persisted per-book choice; unknown / absent → pages.
    static func resolve(persisted: String?) -> ReaderMetricsReadout {
        guard let persisted, let value = ReaderMetricsReadout(rawValue: persisted) else {
            return .pages
        }
        return value
    }

    /// The post-tap readout. With no time readout available (no session
    /// time accrued yet, totals not attached) the tap is inert — the
    /// readout stays pages and the chrome shows no pressed flash.
    func toggled(hasTimeReadout: Bool) -> ReaderMetricsReadout {
        guard hasTimeReadout else { return .pages }
        return self == .pages ? .time : .pages
    }

    /// The label to render: the time readout only when selected AND
    /// available; otherwise the pages readout.
    func displayLabel(pages: String, time: String?) -> String {
        if self == .time, let time { return time }
        return pages
    }
}
