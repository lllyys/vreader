// Purpose: Bug #260 / GH #1130 — the AZW3/MOBI bottom reader chrome.
// Mounts the shared `ReaderBottomChrome` (scrubber + position labels +
// Contents / Notes / Display / AI toolbar) on the live Foliate host,
// which previously mounted NO bottom chrome — the toolbar + reading
// progress were unreachable for an entire major format. The four
// native containers (EPUB / MD / PDF / TXT) each mount this shared
// component in their own `bottomOverlay`; this restores parity for the
// Foliate path.
//
// The toolbar buttons post `.readerOpen*` notifications that
// `ReaderContainerView` already observes (`readerToolbarActionObservers`),
// so wiring Contents / Notes / Display / AI needs no closure plumbing
// here. The scrubber's seek drives `readerAPI.goToFraction` via the
// dedicated `.foliateRequestSeekFraction` notification the spike
// coordinator observes (Bug #260).
//
// @coordinates-with: FoliateBilingualContainerView.swift,
//   FoliateSpikeView.swift, FoliateBottomChromeSeek.swift,
//   ReaderBottomChrome.swift, ReaderNotifications.swift,
//   FoliateBottomChromeLabels.swift

#if canImport(UIKit)
import SwiftUI

extension FoliateBilingualContainerView {

    /// Bug #260: the shared bottom chrome for AZW3/MOBI. Mirrors the
    /// native containers' `bottomOverlay` — same component, same
    /// theme source, same notification-driven toolbar. Continuous
    /// scrubber (no `discreteSteps`) since Foliate reports a smooth
    /// reading `fraction`. The leading label is the chapter title /
    /// percentage; the trailing label is the section position.
    @ViewBuilder
    var bottomChromeOverlay: some View {
        ReaderBottomChrome(
            theme: settingsStore?.theme ?? .paper,
            progress: bottomChromeProgressBinding,
            onSeek: { postSeek($0) },
            leadingLabel: chromeLeadingLabel,
            // Feature #101: the trailing slot is the pages readout (the
            // `FoliateBottomChromeLabels` section position); session time
            // (#345) moved inside the tap-cycled time readout.
            trailingLabel: chromeTrailingLabel,
            timeTrailingLabel: sessionLifecycle?.timeReadoutDisplay,
            bookFingerprintKey: fingerprintKey,
            perBookBaseURL: ReaderContainerView.perBookSettingsBaseURL
        )
    }

    /// Two-way binding to `readingProgress` for the scrubber thumb.
    /// `set` writes the resolved fraction back so the thumb stays where
    /// the user dragged; `get` reflects the latest relocate fraction so
    /// page turns move the thumb.
    private var bottomChromeProgressBinding: Binding<Double> {
        Binding(
            get: { readingProgress },
            set: { readingProgress = $0 }
        )
    }

    /// Bug #260: update the scrubber progress + labels from a Foliate
    /// relocate payload. Reads `fraction` (the reading-progress 0...1),
    /// `tocLabel`, `sectionIndex`, `sectionTotal`. Label text is built
    /// by the pure `FoliateBottomChromeLabels` helper so the formatting
    /// is unit-testable.
    func updateBottomChrome(from userInfo: [AnyHashable: Any]?) {
        if let fraction = userInfo?["fraction"] as? Double {
            readingProgress = max(0, min(1, fraction))
        } else if let fractionInt = userInfo?["fraction"] as? Int {
            readingProgress = max(0, min(1, Double(fractionInt)))
        }
        let labels = FoliateBottomChromeLabels.make(
            tocLabel: userInfo?["tocLabel"] as? String,
            sectionIndex: userInfo?["sectionIndex"] as? Int,
            sectionTotal: userInfo?["sectionTotal"] as? Int,
            fraction: readingProgress
        )
        chromeLeadingLabel = labels.leading
        chromeTrailingLabel = labels.trailing
    }

    /// Bug #260: post a scrubber-seek request. The spike coordinator
    /// (filtered by `fingerprintKey`) evaluates
    /// `readerAPI.goToFraction(<clamped>)` against the live WebView.
    /// The optimistic `readingProgress` write keeps the thumb where the
    /// user dragged until the next relocate confirms the new position.
    private func postSeek(_ fraction: Double) {
        readingProgress = max(0, min(1, fraction))
        NotificationCenter.default.post(
            name: .foliateRequestSeekFraction,
            object: nil,
            userInfo: [
                "fraction": fraction,
                "fingerprintKey": fingerprintKey,
            ]
        )
    }
}
#endif
