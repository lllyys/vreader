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
/// `sectionIndex` scopes a block to one stitched chapter section so
/// per-section translation maps never bleed across sections. It is
/// populated by two renderers:
///   - **Foliate** (feature #56 WI-11, Gate-4 H2): foliate-js keeps
///     multiple section docs loaded at once (paginated preload), so an
///     unscoped enumerate would let one section's blocks bleed into an
///     adjacent section's translation map.
///   - **EPUB continuous-scroll** (feature #71 WI-7): the continuous
///     path stitches multiple chapter `<section data-vreader-spine-index
///     ="N">` blocks into ONE document, each materializing
///     independently and driving its own per-section enumerate
///     (`EPUBBilingualJS.bilingualEnumerateJS(spineIndex:)`).
/// The legacy paged EPUB path (one chapter per document, no section
/// tags) leaves the field `nil` — there is no cross-section hazard
/// there, so it is optional and defaults to `nil`.
struct BilingualBlock: Sendable, Equatable {
    let bid: String
    let text: String
    /// The stitched-section index this block came from — set by the
    /// Foliate renderer and the EPUB continuous-scroll path; `nil` for
    /// the legacy paged EPUB path (one chapter document, no
    /// cross-section leakage).
    let sectionIndex: Int?

    init(bid: String, text: String, sectionIndex: Int? = nil) {
        self.bid = bid
        self.text = text
        self.sectionIndex = sectionIndex
    }
}

/// The parsed shape of a `bilingualEnumerate` JS message.
///
/// Feature #71 WI-7 (Gate-4 round-3 MEDIUM 1): surfaces the
/// `requestedSectionIndex` so the container can
/// `clearBlocks(forSection:)` when a previously-populated stitched
/// section re-enumerates to `[]`. Mirrors
/// `FoliateBilingualEnumeratePayload`.
struct EPUBBilingualEnumeratePayload: Sendable, Equatable {
    /// The stitched section the scoped enumerate walked. `nil` for the
    /// paged/global path (the bare-array shape — one chapter per
    /// document, no per-section identity).
    let requestedSectionIndex: Int?
    /// The enumerated blocks. May be empty even when
    /// `requestedSectionIndex != nil` — that is the "this section
    /// re-enumerated to empty, clear its stale bucket" signal callers
    /// must respect rather than clearing every bucket.
    let blocks: [BilingualBlock]
}

/// Pure glue between the EPUB JS enumerate channel and the bilingual
/// VM's translation cache. Static-only — no instance state.
enum EPUBBilingualPipeline {

    /// Parses a `bilingualEnumerate` message body into a
    /// `[BilingualBlock]`. Drops malformed entries (missing fields,
    /// wrong type, empty `bid` or `text`) and never throws — a partial
    /// enumerate is the right failure mode.
    ///
    /// Feature #71 WI-7: each entry's optional `sectionIndex` (an Int)
    /// is read when present — continuous-scroll mode stitches multiple
    /// chapter `<section>` blocks into one document and the
    /// section-scoped enumerate (`EPUBBilingualJS.bilingualEnumerateJS(
    /// spineIndex:)`) tags every posted block with its section so the
    /// orchestrator can bucket per section with no cross-section
    /// bleed. When the field is absent (paged/global path) it stays
    /// `nil` — backward compatible.
    ///
    /// Accepts BOTH the paged bare-array shape (`[{bid, text}]`) and the
    /// continuous-scroll envelope (`{sectionIndex, blocks}`) — the
    /// envelope's blocks are returned flat. Use `parseEnumeratePayload`
    /// when the caller needs the requested-section identity (to clear an
    /// emptied section's bucket).
    static func parseEnumerateMessage(_ body: Any) -> [BilingualBlock] {
        parseEnumeratePayload(body).blocks
    }

    /// Feature #71 WI-7 (Gate-4 round-3 MEDIUM 1): parses the full payload
    /// including the requested-section identity. The scoped enumerate posts an
    /// envelope `{sectionIndex: N, blocks: [...]}`; the paged/global path posts
    /// the bare `[{bid, text}]` array (no section identity). An empty scoped
    /// envelope still carries `requestedSectionIndex` so the handler can clear
    /// ONLY that section rather than every bucket.
    static func parseEnumeratePayload(_ body: Any) -> EPUBBilingualEnumeratePayload {
        // Continuous-scroll envelope: `{sectionIndex, blocks: [...]}`.
        if let dict = body as? [String: Any] {
            let req = dict["sectionIndex"] as? Int
            let blocks = parseBlocksArray(dict["blocks"] as? [Any] ?? [])
            return EPUBBilingualEnumeratePayload(
                requestedSectionIndex: req, blocks: blocks)
        }
        // Paged/global bare-array shape (one chapter per document). No
        // per-section identity — an empty result cannot be attributed.
        if let array = body as? [Any] {
            return EPUBBilingualEnumeratePayload(
                requestedSectionIndex: nil, blocks: parseBlocksArray(array))
        }
        return EPUBBilingualEnumeratePayload(
            requestedSectionIndex: nil, blocks: [])
    }

    /// Pure block-list parser shared by both payload shapes. Drops malformed
    /// entries (missing fields, wrong type, empty `bid`/`text`).
    private static func parseBlocksArray(_ array: [Any]) -> [BilingualBlock] {
        var blocks: [BilingualBlock] = []
        blocks.reserveCapacity(array.count)
        for raw in array {
            guard let dict = raw as? [String: Any],
                  let bid = dict["bid"] as? String,
                  let text = dict["text"] as? String,
                  !bid.isEmpty, !text.isEmpty else {
                continue
            }
            let sectionIndex = dict["sectionIndex"] as? Int
            blocks.append(BilingualBlock(
                bid: bid, text: text, sectionIndex: sectionIndex))
        }
        return blocks
    }

    /// Maps an ordered `[String]` translation cache onto a `[bid: text]`
    /// table via the shared `BilingualPairing` contract: paired by position
    /// ONLY when `blocks.count == segments.count`.
    ///
    /// Bug #266: a count mismatch (or `translatedSegments == nil`) returns an
    /// empty map → the renderer paints source-only. A partial (min-count)
    /// pairing is exactly the misalignment that put paragraph N's translation
    /// under the wrong paragraph, so it is never produced.
    static func translationsByBid(
        blocks: [BilingualBlock],
        translatedSegments: [String]?
    ) -> [String: String] {
        // Bug #266: pair only on a 1:1 count match (source-only otherwise) via
        // the shared contract — never a wrong paragraph→translation pairing.
        BilingualPairing.translationsByBid(
            blocks: blocks, translatedSegments: translatedSegments)
    }
}
