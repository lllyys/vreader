// Purpose: Feature #56 WI-10 — pure glue between the EPUB
// WKWebView's `bilingualEnumerate` message payload and the
// `BilingualReadingViewModel`'s `translationsByUnit` cache. Sits
// between two boundaries:
//
//   - The JS posts `[{bid, text}]` after stamping each translatable
//     block. The parser here turns that raw `Any` body into a
//     `[BilingualBlock]` value array, drop-by-drop for malformed
//     entries.
//   - The renderer needs a `[String: String]` lookup keyed by the
//     same `bid`s. `translationsByBid(...)` maps the VM's ordered
//     `[String]` cache onto that table by position — the same
//     order the enumerate JS produced.
//
// Both functions are pure (no `@MainActor`, no `await`) so the
// WKWebView coordinator can call them inline from a script-message
// handler without an actor hop. View-layer wiring (subscribing to
// the bilingual VM, dispatching translation, posting inject JS via
// `pendingJS`) lives in `EPUBReaderContainerView+Bilingual`.
//
// Key decisions:
// - **Index-based mapping, not text-based.** The enumerate payload
//   carries `text` for parity / debugging only; the renderer keys
//   by `bid` (the stable attribute the JS stamps) so a non-trivial
//   chapter with repeated paragraph text still injects correctly.
// - **Tolerant parser.** A malformed payload (single bad entry,
//   non-string value, missing field) drops the entry rather than
//   throwing. Translation is a non-critical decoration: a partial
//   render is the right failure mode, not a chapter that refuses
//   to load.
// - **No view dependency.** This file is `import Foundation` only —
//   it doesn't pull `UIKit` or `WebKit`. Tests run as pure
//   value-type assertions.
//
// @coordinates-with: EPUBBilingualJS.swift,
//   EPUBWebViewBridgeCoordinator.swift (the script message
//   producer), BilingualReadingViewModel.swift,
//   EPUBReaderContainerView+Bilingual.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-10)

import Foundation

/// One translatable block discovered by a renderer's
/// `bilingualEnumerate` JS payload. `bid` is the stable
/// `data-vreader-bid` attribute the JS stamped on the block; `text`
/// is the block's source content (whitespace-collapsed). The host
/// translates by index — `bid` is the renderer's lookup key, `text`
/// is for parity / debugging.
///
/// Feature #56 WI-11 (Gate-4 audit finding H2): `sectionIndex` is
/// populated only by the Foliate renderer (`-1` / `nil` for EPUB),
/// because Foliate can keep multiple section docs loaded at the
/// same time and an unscoped enumerate would let one section's
/// blocks bleed into the adjacent section's translation map. The
/// EPUB enumerate is per-spine-document and never has that hazard,
/// so the field is optional and defaults to `nil`.
struct BilingualBlock: Sendable, Equatable {
    let bid: String
    let text: String
    /// Foliate-only: the section index the block came from. `nil`
    /// for EPUB (one chapter document, no cross-section leakage).
    let sectionIndex: Int?

    init(bid: String, text: String, sectionIndex: Int? = nil) {
        self.bid = bid
        self.text = text
        self.sectionIndex = sectionIndex
    }
}

/// Pure glue between the EPUB JS enumerate channel and the bilingual
/// VM's translation cache. Static-only — no instance state.
enum EPUBBilingualPipeline {

    /// Parses a `bilingualEnumerate` message body into a
    /// `[BilingualBlock]`. Drops malformed entries (missing fields,
    /// wrong type, empty `bid` or `text`) and never throws — a partial
    /// enumerate is the right failure mode.
    static func parseEnumerateMessage(_ body: Any) -> [BilingualBlock] {
        guard let array = body as? [Any] else { return [] }
        var blocks: [BilingualBlock] = []
        blocks.reserveCapacity(array.count)
        for raw in array {
            guard let dict = raw as? [String: Any],
                  let bid = dict["bid"] as? String,
                  let text = dict["text"] as? String,
                  !bid.isEmpty, !text.isEmpty else {
                continue
            }
            blocks.append(BilingualBlock(bid: bid, text: text))
        }
        return blocks
    }

    /// Maps an ordered `[String]` translation cache onto a `[bid: text]`
    /// table by position. The two arrays are paired by index — the
    /// enumerate JS and the chapter-translation service share the same
    /// "ordered source segments" contract.
    ///
    /// Mismatched lengths fall back to a partial map: the renderer
    /// injects what it has and leaves the rest as source-only
    /// (silent-source-fallback semantics — plan Decision 2).
    ///
    /// `translatedSegments == nil` means "no cached translation"; the
    /// returned map is empty so the renderer paints source-only.
    static func translationsByBid(
        blocks: [BilingualBlock],
        translatedSegments: [String]?
    ) -> [String: String] {
        guard let segments = translatedSegments, !segments.isEmpty else {
            return [:]
        }
        let count = min(blocks.count, segments.count)
        var map: [String: String] = [:]
        map.reserveCapacity(count)
        for i in 0..<count {
            map[blocks[i].bid] = segments[i]
        }
        return map
    }
}
