// Purpose: Bug #313 — broadcast the live Readium EPUB reading position onto the
// `.readerPositionDidChange` bus.
//
// Every other format host (legacy EPUB, AZW3/Foliate, TXT, MD, PDF) posts
// `.readerPositionDidChange` on each relocate; the Readium host did not, so
// `ReaderContainerView.currentLocator` stayed nil for Readium EPUBs and the
// TOC sheet could neither highlight nor scroll to the current chapter (and the
// AI-panel locator was stale). The host's `onLocationChange` closure now
// delegates to this seam, resolving the relocate to the host's existing
// vreader `Locator` (`currentVReaderLocator(from:)`).
//
// Key decisions:
// - `spineResolved` gates the post on the locator's href being a known spine
//   href. `currentVReaderLocator(from:)` can fall back to a stale enumerated
//   href, and `ReadiumBilingualCommander.normalizedLocator` keeps the raw
//   Readium container-relative href when it can't resolve against the spine —
//   either would post an href that matches no TOC entry (`TOCSheet` matches by
//   exact spine href) and would overwrite a good `currentLocator` with a
//   non-matchable one. Because `normalizedLocator` rewrites a resolvable href to
//   its exact spine form, `spineHrefs.contains(href)` is true precisely when the
//   normalizer resolved the href, so the gate posts every relocate the
//   normalizer can place and skips the rest. (Codex Gate-4 MED.)
// - Known limitation (Codex Gate-4 round-2, tracked as Bug #318): for a book
//   whose spine has duplicate basenames, `normalizedLocator` intentionally
//   leaves an ambiguous href raw (it won't guess), so this gate drops that
//   relocate and the chapter isn't highlighted — the same no-highlight outcome
//   as before this fix, with no AI-locator pollution. This is deliberate: the
//   conservative skip never shows the WRONG chapter, whereas an index-based
//   readingOrder→spine remap would risk exactly that if the two parsers' spine
//   lists ever diverged. The complete fix (a verified-parallel index map) is a
//   separate, low-priority follow-up.
// - `post` is a no-op on a nil locator, so an unresolved relocate (gate
//   returned nil) changes nothing downstream.
// - The `center` parameter exists for test isolation (so a unit test can
//   observe a private `NotificationCenter`); production always posts on
//   `.default`, where `ReaderContainerView` observes.
//
// @coordinates-with: ReadiumEPUBHost+Body.swift (caller),
//   ReadiumEPUBHost+BilingualDriver.swift (currentVReaderLocator),
//   ReadiumEPUBHost+Bilingual.swift (bilingualSpineHrefs),
//   ReaderNotifications.swift (.readerPositionDidChange),
//   ReaderContainerView.swift (consumer), TOCSheet+Support.swift (href match)

import Foundation

/// Posts the live Readium reading position onto the cross-component bus.
enum ReadiumPositionBroadcast {

    /// Returns `vLocator` only when its href can be resolved to a known spine
    /// href — the form the TOC (exact-href match) and the AI panel can use.
    ///
    /// - Primary: the normalized href is already a spine href → use it.
    /// - Bug #318 fallback: for a book whose spine has duplicate basenames,
    ///   `ReadiumBilingualCommander.normalizedLocator` leaves the href RAW (its
    ///   Readium reading-order form), which matches no `spineHrefs` entry. When
    ///   the raw href is found in `readingOrderHrefs`, adopt the OPF spine href at
    ///   that index — but ONLY when the two spine lists are provably parallel
    ///   (equal, non-empty count), so a divergence degrades to the conservative
    ///   skip (returning nil) rather than risk pinning the WRONG chapter.
    ///
    /// Returns nil when the locator is absent, has no href, or carries an
    /// unresolved href that neither matches a spine entry nor maps through the
    /// verified-parallel index — so the caller skips the post and the previous
    /// good `currentLocator` is preserved rather than overwritten.
    static func spineResolved(
        _ vLocator: Locator?,
        spineHrefs: [String],
        readingOrderHrefs: [String] = []
    ) -> Locator? {
        guard let vLocator, let href = vLocator.href else { return nil }
        if spineHrefs.contains(href) { return vLocator }
        // Bug #318: verified-parallel index fallback for duplicate-basename spines.
        guard !readingOrderHrefs.isEmpty,
              readingOrderHrefs.count == spineHrefs.count,
              let idx = readingOrderHrefs.firstIndex(of: href),
              spineHrefs.indices.contains(idx) else {
            return nil
        }
        return vLocator.replacingHref(spineHrefs[idx])
    }

    /// Post `vLocator` as `.readerPositionDidChange`. No-op when `vLocator` is
    /// nil (the relocate couldn't be resolved to a spine href) so a good
    /// `currentLocator` is never overwritten with nothing.
    static func post(_ vLocator: Locator?, on center: NotificationCenter = .default) {
        guard let vLocator else { return }
        center.post(name: .readerPositionDidChange, object: vLocator)
    }
}

private extension Locator {
    /// Bug #318: a copy with `href` replaced, every other field preserved — used to
    /// adopt the verified-parallel OPF spine href for a raw-href relocate.
    func replacingHref(_ newHref: String) -> Locator {
        Locator(
            bookFingerprint: bookFingerprint, href: newHref, progression: progression,
            totalProgression: totalProgression, cfi: cfi, page: page,
            charOffsetUTF16: charOffsetUTF16, charRangeStartUTF16: charRangeStartUTF16,
            charRangeEndUTF16: charRangeEndUTF16, textQuote: textQuote,
            textContextBefore: textContextBefore, textContextAfter: textContextAfter
        )
    }
}
