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

/// Pure math for the Readium bottom-chrome scrubber (extracted so it is
/// unit-testable without a live navigator). Display + seek use the SAME
/// equal-weight spine model so a dragged fraction and the relocate that follows
/// stay consistent (Codex Gate-4 M1 — no exact `positions()` map, which can't
/// take the non-Sendable `Publication` off `@MainActor`).
enum ReadiumBottomChromeSeek {
    /// Seek: whole-book fraction → `(spine index, intra-chapter progression)`.
    static func target(fraction: Double, spineCount: Int) -> (index: Int, intra: Double) {
        guard spineCount > 0 else { return (0, 0) }
        let clamped = max(0, min(1, fraction))
        let scaled = clamped * Double(spineCount)
        let index = min(spineCount - 1, max(0, Int(scaled)))
        let intra = max(0, min(1, scaled - Double(index)))
        return (index, intra)
    }

    /// Display: `(spine index, intra)` → equal-weight whole-book fraction. The
    /// inverse of `target`, so display and seek agree.
    static func progress(index: Int, intra: Double, spineCount: Int) -> Double {
        guard spineCount > 0 else { return 0 }
        let i = min(max(0, index), spineCount - 1)
        return max(0, min(1, (Double(i) + max(0, min(1, intra))) / Double(spineCount)))
    }

    /// Visibility gate parity (Codex Gate-4 M2): the bottom chrome shows only
    /// when the host is ready, the shared chrome is visible, and TTS is idle
    /// (the parent `TTSControlBar` owns the bottom while speaking/paused).
    static func shouldShow(isChromeVisible: Bool, isReady: Bool, ttsIsIdle: Bool) -> Bool {
        isChromeVisible && isReady && ttsIsIdle
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

    /// Whether the bottom chrome should be shown — ready + chrome-visible + TTS
    /// idle, matching every other host's `bottomOverlay` gate (Codex Gate-4 M2).
    var isBottomChromeVisible: Bool {
        let isReady: Bool = { if case .ready = viewModel?.state { return true } else { return false } }()
        let ttsIsIdle = (ttsService?.state ?? .idle) == .idle
        return ReadiumBottomChromeSeek.shouldShow(
            isChromeVisible: isChromeVisible, isReady: isReady, ttsIsIdle: ttsIsIdle)
    }

    /// Update the scrubber thumb + labels from a Readium relocate. Uses the SAME
    /// equal-weight spine model as the seek (Codex Gate-4 M1): the relocate
    /// locator is resolved to its spine index via the host's proven
    /// `currentVReaderLocator` normalization, then `progress(index:intra:)` gives
    /// the whole-book fraction. Falls back to Readium's exact `totalProgression`
    /// only when the spine match is unavailable.
    @MainActor
    func updateBottomChrome(from locator: ReadiumShared.Locator) {
        if let v = currentVReaderLocator(from: locator),
           let href = v.href,
           !bilingualSpineHrefs.isEmpty,
           let idx = bilingualSpineHrefs.firstIndex(of: href) {
            readingProgress = ReadiumBottomChromeSeek.progress(
                index: idx, intra: v.progression ?? 0, spineCount: bilingualSpineHrefs.count)
        } else {
            readingProgress = max(0, min(1, locator.locations.totalProgression ?? readingProgress))
        }
        let pct = Int((readingProgress * 100).rounded())
        let chapter = locator.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        chromeLeadingLabel = (chapter?.isEmpty == false) ? chapter! : "\(pct)%"
        chromeTrailingLabel = "\(pct)%"
    }

    /// Seek to a whole-book fraction. Maps it onto a spine index + intra-chapter
    /// progression (equal-weight, same model as the display) and reuses the WI-9a
    /// `readiumLocator(fromVReader:spineHrefs:)` resolution + the nav commander to
    /// drive `navigator.go(to:)`. The optimistic `readingProgress` write keeps the
    /// thumb where the user dragged until the next relocate.
    @MainActor
    func seekBottomChrome(toFraction fraction: Double) {
        let clamped = max(0, min(1, fraction))
        readingProgress = clamped
        guard !bilingualSpineHrefs.isEmpty else { return }

        let (idx, intra) = ReadiumBottomChromeSeek.target(
            fraction: clamped, spineCount: bilingualSpineHrefs.count)
        let vLocator = Locator(
            bookFingerprint: fingerprint,
            href: bilingualSpineHrefs[idx],
            progression: intra,
            totalProgression: clamped, cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        guard let readiumLocator = ReadiumEPUBReaderViewModel.readiumLocator(
            fromVReader: vLocator, spineHrefs: bilingualSpineHrefs
        ) else { return }
        navCommander.navigate(to: readiumLocator)
    }
}
#endif
