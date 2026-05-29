// Purpose: Feature #42 Phase 1 WI-6 — the pure, nonisolated Readium `Locator` ↔
// `VReaderLocator` envelope mapping pair for the Readium EPUB reader. Extracted
// from `ReadiumEPUBReaderViewModel.swift` to keep that file focused on the open
// lifecycle + debounced save/restore wiring; the mapping is a side-effect-free
// translation that unit-tests without a render.
//
// Key decisions:
// - Authoritative leg is `readiumLocatorJSON` — Readium's own deterministic
//   `jsonString()` (sorted keys, preserves href/type/locations). Decode back via
//   the symmetric `Locator(jsonString:)`.
// - The legacy `Locator` leg is intentionally lossy (href + progression only):
//   it exists so a flag-OFF reopen via the legacy engine's `loadPosition` can
//   resume at an approximate position. Full fidelity lives in the Readium leg.
// - `try?` everywhere — a serialization/decode failure degrades to nil, never
//   throws (the SwiftData-safe posture documented on `VReaderLocator`).
//
// @coordinates-with ReadiumEPUBReaderViewModel.swift, VReaderLocator.swift,
//   Locator.swift

import Foundation
import ReadiumShared

extension ReadiumEPUBReaderViewModel {

    /// Wraps a Readium `Locator` in a durable `VReaderLocator` envelope tagged
    /// `engine: .readium`. The authoritative leg is `readiumLocatorJSON` —
    /// Readium's own deterministic `jsonString()` serialization (sorted keys,
    /// preserves `href`/`type`/`locations`). A best-effort, intentionally lossy
    /// legacy `Locator` (just `href` + `progression`) is also carried so a
    /// flag-OFF reopen can resume at an approximate position. Returns nil only
    /// if Readium fails to serialize the locator (it never should — logged by
    /// the caller).
    nonisolated static func makeVReaderLocator(
        from readiumLocator: ReadiumShared.Locator,
        fingerprintKey: String,
        fingerprint: DocumentFingerprint,
        originalFormat: BookFormat
    ) -> VReaderLocator? {
        guard let json = try? readiumLocator.jsonString() else { return nil }
        let legacy = Locator(
            bookFingerprint: fingerprint,
            href: readiumLocator.href.string,
            progression: readiumLocator.locations.progression,
            totalProgression: readiumLocator.locations.totalProgression,
            cfi: nil, page: nil,
            charOffsetUTF16: nil, charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        return VReaderLocator(
            fingerprintKey: fingerprintKey,
            originalFormat: originalFormat,
            engine: .readium,
            readiumLocatorJSON: json,
            legacyLocator: legacy
        )
    }

    /// Decodes the Readium `Locator` back out of a `.readium` envelope. Returns
    /// nil for a non-Readium envelope, a nil/malformed `readiumLocatorJSON`, or
    /// any decode failure — `try?`, never throws (SwiftData-safe posture).
    nonisolated static func readiumLocator(
        from envelope: VReaderLocator
    ) -> ReadiumShared.Locator? {
        guard envelope.engine == .readium, let json = envelope.readiumLocatorJSON else {
            return nil
        }
        return try? ReadiumShared.Locator(jsonString: json)
    }
}
