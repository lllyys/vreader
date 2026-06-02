// Purpose: Bug #299 — the Readium EPUB host's bottom reader chrome. Mounts the
// shared `ReaderBottomChrome` (progress scrubber + Contents / Notes / Display /
// AI toolbar) on the Readium host, which previously mounted NONE — leaving the
// whole bottom toolbar + reading progress unreachable for EPUB (the primary
// format) after the `readiumEPUBEngine` default flip (2026-06-01). Restores
// parity with the legacy `EPUBReaderContainerView.bottomOverlay` + the Foliate
// #260 mount.
//
// The toolbar buttons post `.readerOpen*` notifications that `ReaderContainerView`
// already observes (`readerToolbarActionObservers`), so wiring Contents / Notes /
// Display / AI needs no closure plumbing here. The scrubber seeks by mapping its
// whole-book 0…1 fraction to a spine index + intra-chapter progression and
// navigating there via the SAME WI-9a `vreader Locator → Readium Locator`
// resolution the TTS-follow + jump paths use (`readiumLocator(fromVReader:)`).
// That reuse avoids Readium's `publication.positions()` (a nonisolated async
// call that can't take the non-Sendable `Publication` off `@MainActor`).
//
// @coordinates-with: ReadiumEPUBHost.swift, ReadiumEPUBHost+Body.swift,
//   ReadiumEPUBHost+Navigation.swift, ReadiumEPUBHost+TTSFollow.swift,
//   ReaderBottomChrome.swift

#if canImport(UIKit)
import SwiftUI
import ReadiumShared

/// Pure seek math for the Readium bottom-chrome scrubber (extracted so it is
/// unit-testable without a live navigator). Maps a whole-book fraction onto an
/// equal-weight spine index + intra-chapter progression.
enum ReadiumBottomChromeSeek {
    /// - Returns: `(index, intra)` where `index` is the clamped spine index and
    ///   `intra` ∈ [0, 1] is the progression within that chapter.
    static func target(fraction: Double, spineCount: Int) -> (index: Int, intra: Double) {
        guard spineCount > 0 else { return (0, 0) }
        let clamped = max(0, min(1, fraction))
        let scaled = clamped * Double(spineCount)
        let index = min(spineCount - 1, max(0, Int(scaled)))
        let intra = max(0, min(1, scaled - Double(index)))
        return (index, intra)
    }
}

extension ReadiumEPUBHost {

    /// Bug #299: the shared bottom chrome for the Readium EPUB host. Continuous
    /// scrubber (no `discreteSteps` — Readium reports a smooth `totalProgression`).
    @ViewBuilder
    var bottomChromeOverlay: some View {
        ReaderBottomChrome(
            theme: settingsStore.theme,
            progress: Binding(get: { readingProgress }, set: { readingProgress = $0 }),
            onSeek: { seekBottomChrome(toFraction: $0) },
            leadingLabel: chromeLeadingLabel,
            trailingLabel: chromeTrailingLabel
        )
    }

    /// Update the scrubber thumb + labels from a Readium relocate.
    /// `totalProgression` is the whole-book reading fraction (0…1); the locator
    /// `title` is the current chapter.
    @MainActor
    func updateBottomChrome(from locator: ReadiumShared.Locator) {
        let total = locator.locations.totalProgression ?? readingProgress
        readingProgress = max(0, min(1, total))
        let pct = Int((readingProgress * 100).rounded())
        let chapter = locator.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        chromeLeadingLabel = (chapter?.isEmpty == false) ? chapter! : "\(pct)%"
        chromeTrailingLabel = "\(pct)%"
    }

    /// Seek to a whole-book fraction. Maps it onto a spine index + intra-chapter
    /// progression (`readingOrder` is read synchronously — no `positions()`), then
    /// reuses the WI-9a `readiumLocator(fromVReader:spineHrefs:)` resolution + the
    /// nav commander to drive `navigator.go(to:)`. The optimistic `readingProgress`
    /// write keeps the thumb where the user dragged until the next relocate.
    @MainActor
    func seekBottomChrome(toFraction fraction: Double) {
        let clamped = max(0, min(1, fraction))
        readingProgress = clamped
        guard case .ready(let publication)? = viewModel?.state else { return }
        let spineHrefs = publication.readingOrder.map(\.href)
        guard !spineHrefs.isEmpty else { return }

        // Equal-weight chapter mapping: fraction → (spine index, intra fraction).
        let (idx, intra) = ReadiumBottomChromeSeek.target(
            fraction: clamped, spineCount: spineHrefs.count)

        let vLocator = Locator(
            bookFingerprint: fingerprint,
            href: spineHrefs[idx],
            progression: intra,
            totalProgression: clamped, cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        guard let readiumLocator = ReadiumEPUBReaderViewModel.readiumLocator(
            fromVReader: vLocator, spineHrefs: spineHrefs
        ) else { return }
        navCommander.navigate(to: readiumLocator)
    }
}
#endif
