// Purpose: Feature #42 WI-10b — TTS speaking-position FOLLOW wiring for the
// Readium EPUB host. TTS already plays renderer-agnostically (WI-10); this slice
// makes the navigator AUTO-ADVANCE so the spoken text stays on screen, mirroring
// the legacy paths' "keep the current sentence visible" intent (TXT/MD via
// `TTSHighlightCoordinator.scrollToOffset`; the Foliate AZW3 path via its own
// JS). Readium owns its spine WebViews, so the follow drives the navigator's
// `go(to:)` (through the already-wired `navCommander`) rather than scrolling a
// WebView directly.
//
// Pipeline:
//   ttsService.currentOffsetUTF16 (flat UTF-16 into the concatenated spine text)
//     → ReadiumTTSFollowMapper.locate(offset:) → (spine href, intra fraction)
//     → throttle (shouldFollow vs last-followed target)
//     → ReadiumEPUBReaderViewModel.readiumLocator(fromVReader:spineHrefs:) (href
//       resolution + RelativeURL + Locations(progression:))
//     → navCommander.navigate(to:) → coordinator → navigator.go(to:)
//
// CRITICAL alignment: the per-spine offset table is built from the SAME spine
// text the TTS engine reads — `EPUBTextExtractor.stripHTML` + trim, skip empties,
// join "\n\n" — via `ReaderAICoordinator.loadBookTextContent`. We reuse the
// host's already-open `bilingualParser` + `bilingualSpineHrefs` to extract that
// text off-main, so the index matches the engine's offsets. If the index were
// built from a different stripper (e.g. the block-preserving variant the
// bilingual path uses) the offsets would drift and the follow would mis-land.
//
// Follow only when: TTS state == .speaking AND a mapper is built for THIS book.
// Stops following on pause/stop (the offset stops advancing; on stop the engine
// resets the offset to 0, which the throttle treats as a backward jump but the
// `.speaking` guard suppresses). The observers are torn down with the host body.
//
// SwiftUI `@State` cannot live in an extension, so the stored follow state lives
// on `ReadiumEPUBHost` (in `ReadiumEPUBHost.swift`); this file owns the build +
// follow methods + the observers modifier.
//
// @coordinates-with: ReadiumEPUBHost.swift, ReadiumTTSFollowMapper.swift,
//   ReadiumEPUBReaderViewModel+Navigation.swift, ReadiumNavCommander (in
//   ReadiumEPUBHost+Navigation.swift), ReaderAICoordinator.swift,
//   EPUBTextExtractor.swift, TTSService.swift

#if canImport(UIKit)
import SwiftUI
import ReadiumShared
import OSLog

extension ReadiumEPUBHost {

    private static let ttsFollowLog = Logger(
        subsystem: "com.vreader.app", category: "ReadiumTTSFollow"
    )

    /// Intra-spine fraction drift past which an in-chapter spoken position is
    /// re-navigated. A spine (href) change always follows regardless. ~1/12 of a
    /// chapter keeps the spoken text on screen without driving the navigator on
    /// every `willSpeakRange` word callback (the legacy TXT path re-scrolls per
    /// sentence; a web navigator is coarsened here to avoid thrash).
    private var ttsFollowFractionThreshold: Double { 0.08 }

    /// Builds the per-spine follow offset table from the host's already-open
    /// `bilingualParser` (the SAME `EPUBParser` + OPF-relative spine the bilingual
    /// path uses). The extraction + strip runs OFF the main actor via the mapper's
    /// `nonisolated` builder (Gate-4 round-1 Medium: a per-spine `stripHTML` walk
    /// over a large CJK book must not block the UI). It replicates the TTS feed
    /// exactly — `EPUBTextExtractor.stripHTML` (the whitespace-collapsing variant
    /// `loadBookTextContent` uses, NOT the block-preserving bilingual one),
    /// trimmed, empties skipped. Idempotent — an already-built mapper is kept; only
    /// the final `@State` assignment lands on `@MainActor`.
    func buildTTSFollowMapperIfNeeded() async {
        guard ttsService != nil else { return }
        guard ttsFollowMapper == nil else { return }
        guard let parser = bilingualParser, !bilingualSpineHrefs.isEmpty else { return }
        let entries = await ReadiumTTSFollowMapper.buildEntries(
            spineHrefs: bilingualSpineHrefs, parser: parser
        )
        // Re-check after the off-main hop: a concurrent build (or teardown) may
        // have set the mapper already.
        guard ttsFollowMapper == nil else { return }
        ttsFollowMapper = ReadiumTTSFollowMapper(entries: entries)
        Self.ttsFollowLog.info("built TTS follow map: \(entries.count, privacy: .public) non-empty spines")
    }

    /// Handles a TTS offset change: maps the flat offset → (href, fraction), runs
    /// the throttle, and (if it should follow) drives the navigator via
    /// `navCommander`. No-op unless TTS is speaking and a mapper exists. The
    /// publication's reading-order hrefs resolve the OPF-relative spine href onto
    /// Readium's container-relative form (the WI-9a jump path's exact mapping).
    func handleTTSOffsetChange(_ offset: Int, spineHrefs: [String]) {
        guard let tts = ttsService, tts.state == .speaking else { return }
        guard let mapper = ttsFollowMapper, !mapper.isEmpty else { return }
        guard let target = mapper.locate(offset: offset) else { return }
        guard ReadiumTTSFollowMapper.shouldFollow(
            previous: lastFollowedTTSTarget,
            current: target,
            fractionThreshold: ttsFollowFractionThreshold
        ) else { return }

        // Build a minimal vreader Locator (href + progression) and map it onto a
        // Readium Locator via the same WI-9a resolution the jump path uses.
        let vLocator = Locator(
            bookFingerprint: fingerprint,
            href: target.href,
            progression: target.fraction,
            totalProgression: nil, cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        guard let readiumLocator = ReadiumEPUBReaderViewModel.readiumLocator(
            fromVReader: vLocator, spineHrefs: spineHrefs
        ) else { return }
        lastFollowedTTSTarget = target
        navCommander.navigate(to: readiumLocator)
        Self.ttsFollowLog.info(
            "follow nav: offset=\(offset, privacy: .public) → href=\(target.href, privacy: .public) frac=\(target.fraction, privacy: .public)"
        )
    }

    /// Resets the follow cursor so a fresh play session re-navigates from its
    /// first spoken position (otherwise a restart at a position close to where the
    /// last session stopped would be throttled away).
    func resetTTSFollowCursor() {
        lastFollowedTTSTarget = nil
    }

    /// Wraps `wrapped` with the TTS-follow `.onChange` observers. Kept here (not in
    /// the host body) for the host's 300-line budget — mirrors `+Highlights`'
    /// `highlightObservers`. `spineHrefs` is the publication's container-relative
    /// reading-order, captured in the `.ready` case where the publication is bound.
    /// Implemented as a `some View` helper (not a `ViewModifier` struct) so the
    /// `.onChange` chain type-checks against a concrete `View` rather than the
    /// `ViewModifier.Content` existential (Swift fails the conformance otherwise).
    @MainActor @ViewBuilder
    func ttsFollowObservers<V: View>(_ wrapped: V, spineHrefs: [String]) -> some View {
        wrapped
            // Gate-4 round-1 Medium: if TTS is ALREADY speaking when this `.ready`
            // navigator mounts (e.g. the host re-mounted mid-playback), the
            // `.onChange(of: state)` below never fires — so build the mapper +
            // follow the current position here at mount. `.task` runs once when the
            // navigator appears; cancelled on disappear (no leak).
            .task {
                guard ttsService?.state == .speaking else { return }
                resetTTSFollowCursor()
                await buildTTSFollowMapperIfNeeded()
                if let offset = ttsService?.currentOffsetUTF16 {
                    handleTTSOffsetChange(offset, spineHrefs: spineHrefs)
                }
            }
            .onChange(of: ttsService?.state) { _, newState in
                if newState == .speaking {
                    resetTTSFollowCursor()
                    Task { await buildTTSFollowMapperIfNeeded() }
                } else if newState == .idle || newState == nil {
                    resetTTSFollowCursor()
                }
                // `.paused` keeps the cursor — resume continues following.
            }
            .onChange(of: ttsService?.currentOffsetUTF16) { _, newOffset in
                if let newOffset {
                    handleTTSOffsetChange(newOffset, spineHrefs: spineHrefs)
                }
            }
    }
}
#endif
