// Purpose: Bug #324 / GH #1546 regression tests — TXT/MD selection (caret, grab
// handles, selection-highlight) must use the reader theme accent
// (`TXTViewConfig.accentColor`) as the `UITextView.tintColor`, not the system
// default blue. Covers all three TXT/MD UITextView surfaces:
//  1. Non-chunked scroll bridge (`TXTTextViewBridge.applyTintColor`)
//  2. Chunked large-file bridge (`TXTChunkedReaderBridge.applyTintColor`)
//  3. Native paged container (`NativePagedContainer.applyConfig`)
// and the theme-change refresh path (a second config with a different accent
// updates the live `tintColor`).
//
// @coordinates-with: TXTTextViewBridge.swift, TXTChunkedReaderBridge.swift,
//   NativeTextPagedView.swift, TXTViewConfig.swift

#if canImport(UIKit)
import Testing
import UIKit
@testable import vreader

@Suite("TXT/MD selection tint — bug #324 / GH #1546")
@MainActor
struct TXTSelectionTintTests {

    private static let accentA = UIColor(red: 0.80, green: 0.20, blue: 0.10, alpha: 1.0)
    private static let accentB = UIColor(red: 0.10, green: 0.40, blue: 0.90, alpha: 1.0)

    private func config(accent: UIColor) -> TXTViewConfig {
        var c = TXTViewConfig()
        c.accentColor = accent
        return c
    }

    // MARK: - Non-chunked scroll bridge

    @Test("non-chunked bridge applies config.accentColor as tintColor")
    func nonChunkedAppliesAccentTint() {
        let textView = HighlightableTextView()
        TXTTextViewBridge.applyTintColor(to: textView, config: config(accent: Self.accentA))
        #expect(textView.tintColor == Self.accentA)
    }

    @Test("non-chunked bridge refreshes tintColor on theme (accent) change")
    func nonChunkedRefreshesAccentTint() {
        let textView = HighlightableTextView()
        TXTTextViewBridge.applyTintColor(to: textView, config: config(accent: Self.accentA))
        #expect(textView.tintColor == Self.accentA)
        // Live theme switch: a new config with a different accent must update.
        TXTTextViewBridge.applyTintColor(to: textView, config: config(accent: Self.accentB))
        #expect(textView.tintColor == Self.accentB)
    }

    // MARK: - Chunked large-file bridge

    @Test("chunked bridge applies config.accentColor as the cell textView tintColor")
    func chunkedAppliesAccentTint() {
        let textView = HighlightableTextView()
        TXTChunkedReaderBridge.applyTintColor(to: textView, config: config(accent: Self.accentA))
        #expect(textView.tintColor == Self.accentA)
    }

    @Test("chunked bridge refreshes tintColor on theme (accent) change")
    func chunkedRefreshesAccentTint() {
        let textView = HighlightableTextView()
        TXTChunkedReaderBridge.applyTintColor(to: textView, config: config(accent: Self.accentA))
        TXTChunkedReaderBridge.applyTintColor(to: textView, config: config(accent: Self.accentB))
        #expect(textView.tintColor == Self.accentB)
    }

    // MARK: - Native paged container

    @Test("paged container applies config.accentColor as tintColor")
    func pagedAppliesAccentTint() {
        let container = NativePagedContainer()
        container.applyConfig(config(accent: Self.accentA))
        #expect(container.textView.tintColor == Self.accentA)
    }

    @Test("paged container refreshes tintColor on theme (accent) change")
    func pagedRefreshesAccentTint() {
        let container = NativePagedContainer()
        container.applyConfig(config(accent: Self.accentA))
        container.applyConfig(config(accent: Self.accentB))
        #expect(container.textView.tintColor == Self.accentB)
    }
}

#endif
