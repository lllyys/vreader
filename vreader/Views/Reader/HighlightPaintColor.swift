// Purpose: Defines `PaintedHighlight` — the (range + stored-color-name)
// value the TXT/MD highlight painter threads from `TextReaderUIState` down
// to `HighlightingLayoutManager` — and `HighlightPaintColor`, which
// resolves a stored color name into the translucent fill the painter draws.
//
// Bug #208 / GH #776: before this type existed the TXT/MD painter carried
// bare `NSRange`s and `HighlightableTextView` hardcoded a single yellow
// fill, so a highlight the user saved as pink/green/blue still rendered
// yellow. `PaintedHighlight` carries `HighlightRecord.color` through the
// whole render pipeline; `HighlightPaintColor.fill(for:)` maps it to a
// `UIColor` at paint time.
//
// Key decisions:
// - `PaintedHighlight` carries the raw stored color *name* (a `String`),
//   not a resolved `UIColor`, so it stays Foundation-only — the non-UIKit
//   `ReaderNotificationHandlers` / `TXTChapterHighlightHelper` thread it
//   without importing UIKit. Resolution to a `UIColor` happens once, at
//   paint time, inside `HighlightingLayoutManager`.
// - Unknown / legacy color values fall back to yellow, mirroring
//   `FoliateHighlightRenderer.foliateColor(from:)`'s default — a stored
//   value outside the named picker must never crash or render blank.
// - The fill palette is pinned to `NamedHighlightColor.hex` (the committed
//   design swatch values), so a painted highlight matches the
//   SelectionPopover swatch the user tapped.
//
// @coordinates-with: HighlightableTextView.swift, TextReaderUIState.swift,
//   TextHighlightRenderer.swift, TXTChapterHighlightHelper.swift,
//   TXTChunkedHighlightHelper.swift, NamedHighlightColor.swift

import Foundation

/// One persisted highlight ready to render: its character range plus the
/// stored color name (`HighlightRecord.color`). Threaded from
/// `TextReaderUIState.persistedHighlightRanges` through the TXT/MD bridges
/// and chapter/chunk translation helpers down to the layout-manager
/// painter, which resolves `colorName` via `HighlightPaintColor.fill(for:)`.
///
/// Foundation-only on purpose — `colorName` is the raw stored string, so
/// this value flows through the non-UIKit notification handlers and the
/// chapter helper without an `import UIKit`.
struct PaintedHighlight: Sendable, Equatable {
    /// Character range (UTF-16) painted, in the coordinate space of the
    /// text view currently rendering it (document-global, chapter-local,
    /// or chunk-local depending on where in the pipeline the value sits).
    let range: NSRange
    /// Raw stored color name from `HighlightRecord.color` — the lowercased
    /// semantic name ("yellow"/"pink"/"green"/"blue"), or a legacy/unknown
    /// value. Resolved to a fill color by `HighlightPaintColor.fill(for:)`.
    let colorName: String

    init(range: NSRange, colorName: String) {
        self.range = range
        self.colorName = colorName
    }
}

#if canImport(UIKit)
import UIKit

/// Resolves a stored highlight color name into the translucent `UIColor`
/// the TXT/MD layout-manager painter fills. The transient search /
/// navigation highlight uses its own fixed yellow (`searchHighlight`).
enum HighlightPaintColor {

    /// Opacity applied to the opaque design swatch so the reader text
    /// stays legible beneath a highlight. Matches the alpha the TXT
    /// painter used before Bug #208 (`systemYellow` at 0.4).
    static let fillAlpha: CGFloat = 0.4

    /// Fixed fill for the transient search / navigation highlight — the
    /// short-lived flash a search-result tap paints. Distinct from a
    /// persisted highlight: it carries no user-chosen color, and Bug #208
    /// deliberately leaves it on `systemYellow` (its pre-#208 value)
    /// rather than moving it onto the design palette.
    static let searchHighlight: UIColor =
        UIColor.systemYellow.withAlphaComponent(fillAlpha)

    /// Resolves `HighlightRecord.color` into the translucent fill for a
    /// persisted highlight. Recognised names map to the
    /// `NamedHighlightColor` design swatch; any unrecognised value
    /// (legacy hex, empty string, a future custom color) falls back to
    /// yellow — mirroring `FoliateHighlightRenderer.foliateColor(from:)`.
    static func fill(for storedColorName: String) -> UIColor {
        solidSwatch(for: storedColorName).withAlphaComponent(fillAlpha)
    }

    /// Feature #74: the OPAQUE design swatch for a stored color name — the hue the
    /// locate-bloom focus ring strokes and the glow tints. Same resolution +
    /// yellow fallback as `fill(for:)`, but without the wash alpha applied.
    static func solidSwatch(for storedColorName: String) -> UIColor {
        let named = NamedHighlightColor.from(storageString: storedColorName) ?? .yellow
        return uiColor(fromHex: named.hex) ?? UIColor.systemYellow
    }

    /// Feature #74: the swatch fill at an explicit `alpha` — the variable-alpha
    /// wash the locate bloom value-lifts (0.4 resting → 0.86 peak). The fixed
    /// `fill(for:)` (resting `fillAlpha`) is unchanged.
    static func fill(for storedColorName: String, alpha: CGFloat) -> UIColor {
        solidSwatch(for: storedColorName).withAlphaComponent(alpha)
    }

    /// Parses a `#RRGGBB` hex string into an opaque `UIColor`. Returns nil
    /// for malformed input so `fill(for:)` can fall back. Only the 6-digit
    /// form is needed — `NamedHighlightColor.hex` never emits alpha.
    private static func uiColor(fromHex hex: String) -> UIColor? {
        var trimmed = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("#") { trimmed.removeFirst() }
        guard trimmed.count == 6, let value = UInt32(trimmed, radix: 16) else {
            return nil
        }
        return UIColor(
            red: CGFloat((value >> 16) & 0xff) / 255.0,
            green: CGFloat((value >> 8) & 0xff) / 255.0,
            blue: CGFloat(value & 0xff) / 255.0,
            alpha: 1.0
        )
    }
}
#endif
