// Purpose: Feature #42 WI-10b — the pure, value-type core of TTS speaking-position
// FOLLOW for the Readium EPUB host. Maps the flat UTF-16 offset the TTS engine
// reports (`TTSService.currentOffsetUTF16`) back to a (spine href, intra-spine
// fraction) the Readium navigator can `go(to:)`, and decides WHEN a position
// change is worth navigating (the throttle — so the navigator tracks the spoken
// text without thrashing on every word).
//
// CRITICAL extraction-alignment contract: the per-spine offset table MUST be
// built from the SAME concatenation the TTS engine reads. For EPUB that text is
// `ReaderAICoordinator.loadBookTextContent` — per-spine `EPUBTextExtractor.stripHTML`
// + `.trimmingCharacters(.whitespacesAndNewlines)`, SKIPPING empties, then
// `.joined(separator: "\n\n")`. `buildEntries(spineTexts:)` replicates that exactly
// (skip-empty + the 2-UTF-16 separator) so a flat offset maps to the spine the
// engine is actually speaking. If the index were built from a DIFFERENT extraction
// (e.g. the block-preserving stripper, or without skipping empties) the offsets
// would drift and the follow would land on the wrong chapter.
//
// Key decisions:
// - Value type (`struct`), `Sendable`, no UIKit — unit-tested without a render.
// - `locate(offset:)` clamps out-of-range offsets to the nearest valid position
//   (negative → first spine f=0; separator gap → preceding spine f=1.0; past end
//   → last spine f=1.0) so the follow never stalls on a boundary offset.
// - The throttle (`shouldFollow`) navigates on ANY spine change, or an intra-spine
//   fraction drift beyond `fractionThreshold` — mirroring the legacy TXT path's
//   "keep the spoken sentence visible" intent (the legacy path re-scrolls per
//   sentence; for a paginated/scrolled web navigator we coarsen to ~chapter-eighth
//   so the navigator isn't driven on every `willSpeakRange` word callback).
//
// @coordinates-with vreader/Views/Reader/ReadiumEPUBHost+TTSFollow.swift,
//   vreader/Views/Reader/ReaderAICoordinator.swift (loadBookTextContent),
//   vreader/Services/Search/EPUBTextExtractor.swift (stripHTML)

import Foundation

/// Pure mapper + throttle for Readium TTS speaking-position follow (feature #42
/// WI-10b). Maps a flat UTF-16 offset into the concatenated spine text back to a
/// (spine href, intra-spine fraction) and decides whether a position change is
/// worth driving the navigator.
struct ReadiumTTSFollowMapper: Sendable, Equatable {

    /// One non-empty spine document's span within the concatenated TTS text.
    /// `start` / `length` are UTF-16 units into the joined string.
    struct Entry: Sendable, Equatable {
        let href: String
        let start: Int
        let length: Int
    }

    /// A resolved follow target: which spine the offset falls in + the intra-spine
    /// progression (0.0...1.0) the navigator should land at.
    typealias Target = (href: String, fraction: Double)

    private let entries: [Entry]

    init(entries: [Entry]) {
        self.entries = entries
    }

    /// `true` when no spine document produced text (image-only book / extraction
    /// failure) — the follow is inert.
    var isEmpty: Bool { entries.isEmpty }

    // MARK: - Table builder

    /// Builds the per-spine offset table from per-spine plain text, replicating
    /// `ReaderAICoordinator.loadBookTextContent`'s EPUB concatenation: trim each
    /// spine's text, SKIP empties, and account for the 2-UTF-16 `"\n\n"` separator
    /// between adjacent non-empty entries.
    ///
    /// `spineTexts` is in reading order; `text` is the ALREADY-stripped plain text
    /// (the caller runs `EPUBTextExtractor.stripHTML` off-main, matching the TTS
    /// feed). Trimming here mirrors the feed's `.trimmingCharacters` step so a
    /// caller that passes raw-stripped (untrimmed) text still aligns.
    static func buildEntries(spineTexts: [(href: String, text: String)]) -> [Entry] {
        let separatorLength = "\n\n".utf16.count // 2
        var entries: [Entry] = []
        var cursor = 0
        for (href, raw) in spineTexts {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            // Insert the separator BEFORE every entry except the first.
            if !entries.isEmpty { cursor += separatorLength }
            let length = trimmed.utf16.count
            entries.append(Entry(href: href, start: cursor, length: length))
            cursor += length
        }
        return entries
    }

    /// Builds the entry table off the main actor: walks the spine via the
    /// (actor-isolated) parser, strips each doc's HTML with the SAME stripper the
    /// TTS feed uses (`EPUBTextExtractor.stripHTML`), then folds via `buildEntries`.
    /// `nonisolated` so the per-spine strip (CPU-heavy for large CJK books) does
    /// NOT run on `@MainActor` — the host only assigns the returned `[Entry]` to
    /// its `@State` on the main actor (Gate-4 round-1 Medium). A failed spine read
    /// contributes empty text (skipped by `buildEntries`), matching the TTS feed's
    /// `try?` skip.
    nonisolated static func buildEntries(
        spineHrefs: [String],
        parser: any EPUBParserProtocol
    ) async -> [Entry] {
        var spineTexts: [(href: String, text: String)] = []
        spineTexts.reserveCapacity(spineHrefs.count)
        for href in spineHrefs {
            if let xhtml = try? await parser.contentForSpineItem(href: href) {
                spineTexts.append((href: href, text: EPUBTextExtractor.stripHTML(xhtml)))
            } else {
                spineTexts.append((href: href, text: ""))
            }
        }
        return buildEntries(spineTexts: spineTexts)
    }

    // MARK: - Mapping

    /// Maps a flat UTF-16 `offset` to a (spine href, intra-spine fraction). Returns
    /// nil only when the mapper has NO entries. Out-of-range offsets clamp:
    /// - negative → first spine, fraction 0.0
    /// - inside a separator gap → the PRECEDING spine, fraction 1.0
    /// - past the last content char → last spine, fraction 1.0
    func locate(offset: Int) -> Target? {
        guard let first = entries.first, let last = entries.last else { return nil }
        if offset <= first.start {
            return (href: first.href, fraction: 0.0)
        }
        // Binary search for the entry whose [start, start+length) contains offset.
        var lo = 0, hi = entries.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let e = entries[mid]
            if offset < e.start {
                hi = mid - 1
            } else if offset >= e.start + e.length {
                // Past this entry's content. If the NEXT entry starts after this
                // offset (i.e. offset is in the separator gap), clamp to this
                // entry's end (fraction 1.0). Otherwise keep searching forward.
                if mid + 1 < entries.count, offset >= entries[mid + 1].start {
                    lo = mid + 1
                } else {
                    return (href: e.href, fraction: 1.0)
                }
            } else {
                let intra = Double(offset - e.start) / Double(e.length)
                return (href: e.href, fraction: min(max(intra, 0.0), 1.0))
            }
        }
        // Past everything → last spine end.
        return (href: last.href, fraction: 1.0)
    }

    // MARK: - Throttle

    /// Decides whether a newly-resolved spoken `current` target is worth driving
    /// the navigator to, given the LAST target we actually followed to.
    ///
    /// Follows when: there is no previous target (first follow), the spine href
    /// changed (always — a chapter crossing), or the intra-spine fraction moved by
    /// more than `fractionThreshold` (forward OR backward). This keeps the spoken
    /// text on screen without re-navigating on every `willSpeakRange` word.
    static func shouldFollow(
        previous: Target?,
        current: Target,
        fractionThreshold: Double
    ) -> Bool {
        guard let previous else { return true }
        if previous.href != current.href { return true }
        return abs(current.fraction - previous.fraction) > fractionThreshold
    }
}
