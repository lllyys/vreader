// Purpose: Feature #56 WI-11 — pure glue between the Foliate
// WKWebView's `bilingualEnumerate` message payload and the
// `BilingualReadingViewModel`'s `translationsByUnit` cache. Mirror
// of `EPUBBilingualPipeline` for the AZW3/MOBI live path; reuses
// the `BilingualBlock` value type so a single ordered enumerate
// → translate → inject contract is shared across formats.
//
// Sits between two boundaries:
//
//   - The JS posts `[{bid, text}]` after stamping each translatable
//     block on the current Foliate section's DOM. The parser here
//     turns that raw `Any` body into a `[BilingualBlock]` value
//     array, drop-by-drop for malformed entries.
//   - The renderer needs a `[String: String]` lookup keyed by the
//     same `bid`s. `translationsByBid(...)` maps the VM's ordered
//     `[String]` cache onto that table by position — the same
//     order the enumerate JS produced.
//
// Both functions are pure (no `@MainActor`, no `await`) so the
// WKWebView coordinator can call them inline from a script-message
// handler without an actor hop. View-layer wiring (subscribing to
// the bilingual VM, dispatching translation, posting inject JS via
// the bridge's pending-JS seam) lives in
// `FoliateSpikeView+Bilingual`.
//
// Key decisions:
// - **Re-uses `BilingualBlock`.** The value type that WI-10 added
//   already has the `{bid, text}` shape and `Sendable` /
//   `Equatable` conformances we need. Defining a parallel
//   `FoliateBilingualBlock` would fork an identity that does not
//   carry any format-specific state.
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
// @coordinates-with: FoliateBilingualJS.swift,
//   FoliateSpikeView.swift (the script message producer),
//   BilingualReadingViewModel.swift,
//   EPUBBilingualPipeline.swift (sibling EPUB renderer pipeline),
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-11)

import Foundation

/// The parsed shape of a `bilingualEnumerate` JS message.
/// Gate-4 round-3 audit fix: surfaces the
/// `requestedSectionIndex` so the container can
/// `clearBlocks(forSection:)` when a previously-populated section
/// re-enumerates to `[]`.
struct FoliateBilingualEnumeratePayload: Sendable, Equatable {
    /// The section index the caller asked the JS host to enumerate.
    /// `nil` means a bulk walk (the host walked every loaded
    /// section) — used by older bundles or the legacy initial
    /// enumerate.
    let requestedSectionIndex: Int?
    /// The enumerated blocks. May be empty even when
    /// `requestedSectionIndex != nil` — that's the "section
    /// re-enumerated to empty" signal callers must respect.
    let blocks: [BilingualBlock]
}

/// Pure glue between the Foliate JS enumerate channel and the
/// bilingual VM's translation cache. Static-only — no instance
/// state. Mirror of `EPUBBilingualPipeline`.
enum FoliateBilingualPipeline {

    /// Parses a `bilingualEnumerate` message body into a
    /// `[BilingualBlock]`. Drops malformed entries (missing fields,
    /// wrong type, empty `bid` or `text`) and never throws — a partial
    /// enumerate is the right failure mode.
    ///
    /// Gate-4 audit finding H2: blocks now carry the
    /// per-section index the JS host attached to each entry. Foliate
    /// can keep multiple sections loaded at once
    /// (`view.renderer.getContents()` returns one entry per loaded
    /// section); the sectionIndex tag lets
    /// `blocks(_:forSection:)` scope translations to the current
    /// unit without bleeding across adjacent sections.
    ///
    /// Accepts both the wrapped shape
    /// (`{requestedSectionIndex, blocks}` — current bundle) and the
    /// legacy bare-array shape (older bundle). The bare-array path
    /// drops the requested-section signal — callers cannot detect
    /// "re-enumerated to empty" against an older bundle.
    static func parseEnumerateMessage(_ body: Any) -> [BilingualBlock] {
        return parseEnumeratePayload(body).blocks
    }

    /// Gate-4 round-3 audit fix: parses the full
    /// payload including the requested-section signal. Use this
    /// when the caller needs to call `clearBlocks(forSection:)` on
    /// an empty enumerate.
    static func parseEnumeratePayload(_ body: Any) -> FoliateBilingualEnumeratePayload {
        // New wrapped shape: `{requestedSectionIndex, blocks: [...]}`.
        if let dict = body as? [String: Any] {
            let req = dict["requestedSectionIndex"] as? Int
            let blocks = parseBlocksArray(dict["blocks"] as? [Any] ?? [])
            return FoliateBilingualEnumeratePayload(
                requestedSectionIndex: req, blocks: blocks)
        }
        // Legacy bare-array shape: drops the requested-section
        // signal but still works for older bundles.
        if let array = body as? [Any] {
            return FoliateBilingualEnumeratePayload(
                requestedSectionIndex: nil,
                blocks: parseBlocksArray(array)
            )
        }
        return FoliateBilingualEnumeratePayload(
            requestedSectionIndex: nil, blocks: [])
    }

    /// Pure block-list parser shared by both payload shapes.
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

    /// Filters an enumerate payload down to the blocks belonging to
    /// `sectionIndex`. Untagged blocks (`sectionIndex == nil`) are
    /// preserved when no other section matches — this keeps older
    /// foliate bundles compatible.
    ///
    /// Gate-4 audit finding H2: this is the seam that prevents one
    /// unit's translations from spilling into adjacent loaded
    /// sections in paginated mode.
    static func blocks(
        _ blocks: [BilingualBlock],
        forSection sectionIndex: Int
    ) -> [BilingualBlock] {
        let scoped = blocks.filter { $0.sectionIndex == sectionIndex }
        if !scoped.isEmpty { return scoped }
        // Fallback for older bundles: if NO blocks carry a section
        // tag, return the unchanged list (the original WI-11 r0
        // behaviour). A mixed payload (some tagged, some not) keeps
        // only the matching-section entries.
        let untagged = blocks.contains { $0.sectionIndex != nil }
        return untagged ? [] : blocks
    }

    /// Maps an ordered `[String]` translation cache onto a `[bid: text]`
    /// table via the shared `BilingualPairing` contract: paired by position
    /// ONLY when `blocks.count == segments.count`.
    ///
    /// Bug #266: a count mismatch (or `translatedSegments == nil`) returns an
    /// empty map → source-only. AZW3/MOBI shares EPUB's nested-block
    /// double-count (`foliate-host.js` walks `getElementsByTagName('*')`), so
    /// on a nested chapter `blocks > segments` and this returns source-only —
    /// fail-safe (never a wrong pairing) until the host enumerate is leaf-fixed.
    static func translationsByBid(
        blocks: [BilingualBlock],
        translatedSegments: [String]?
    ) -> [String: String] {
        BilingualPairing.translationsByBid(
            blocks: blocks, translatedSegments: translatedSegments)
    }
}
