// Purpose: Circular reading-progress ring for the Library list row
// (feature #60 visual identity v2, WI-8).
//
// Key decisions:
// - Mirrors the design `ListView`'s trailing SVG ring: a faint warm
//   track circle under an oxblood arc that sweeps clockwise from the
//   12 o'clock position.
// - Geometry comes from `LibraryCardTokens` — a 30pt box holds a
//   radius-12 circle (24pt drawn diameter) stroked at 2pt, so the
//   visible ring is inset 3pt inside the row's trailing slot.
// - `progress` is defensively clamped to `[0, 1]` so a stored
//   `totalProgression` past 1 (rounding drift) cannot over-sweep the
//   arc; callers should only mount the ring for in-progress books.
//
// @coordinates-with: BookRowView.swift, LibraryCardTokens.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-library.jsx`

import SwiftUI

/// A circular progress ring for the Library list row — a faint track
/// circle under an oxblood arc sweeping clockwise from 12 o'clock.
struct LibraryProgressRing: View {
    /// Reading-progress fraction; clamped to `[0, 1]` before drawing.
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    LibraryCardTokens.progressRingTrack,
                    lineWidth: LibraryCardTokens.progressRingLineWidth
                )
            Circle()
                .trim(from: 0, to: clampedProgress)
                .stroke(
                    LibraryCardTokens.accent,
                    style: StrokeStyle(
                        lineWidth: LibraryCardTokens.progressRingLineWidth,
                        lineCap: .round
                    )
                )
                // SwiftUI trims from 3 o'clock; rotate so the arc
                // starts at 12 o'clock like the design SVG.
                .rotationEffect(.degrees(-90))
        }
        .frame(width: ringDiameter, height: ringDiameter)
        .padding(LibraryCardTokens.progressRingInset)
        .accessibilityHidden(true)
    }

    /// Drawn circle diameter — the 30pt box minus a 3pt inset each side.
    private var ringDiameter: CGFloat {
        LibraryCardTokens.progressRingSize
            - LibraryCardTokens.progressRingInset * 2
    }

    /// `progress` clamped into `[0, 1]` — NaN collapses to 0.
    private var clampedProgress: CGFloat {
        guard progress.isFinite else { return 0 }
        return CGFloat(min(max(progress, 0), 1))
    }
}
