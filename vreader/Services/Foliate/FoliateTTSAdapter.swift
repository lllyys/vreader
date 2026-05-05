// Purpose: Adapter between Foliate-js TTS output and AVSpeechSynthesizer input.
// Generates JS strings for TTS control and parses tts-text message payloads
// into plain text + word boundary marks suitable for AVSpeechUtterance.
//
// Key decisions:
// - Pure static functions, no side effects, no state.
// - Accepts Any to match WKScriptMessage.body type.
// - Returns nil for invalid payloads (caller decides error handling).
// - Mark names are escaped for safe JS string injection.
// - Malformed marks in the array are silently skipped (partial parse).
//
// @coordinates-with: FoliateMessageParser.swift, TTSService.swift, foliate-host.js

import Foundation

/// A TTS text block from Foliate-js containing plain text and word boundary marks.
struct FoliateTTSBlock: Sendable, Equatable {
    let text: String
    let marks: [FoliateTTSMark]
}

/// A word boundary mark within a TTS block, identifying a segment by character offsets.
struct FoliateTTSMark: Sendable, Equatable {
    let name: String
    let start: Int
    let end: Int
}

enum FoliateTTSAdapter {

    /// Generate JS to initialize TTS in Foliate-js with the given granularity.
    /// - Parameter granularity: Segmentation level ("word" or "sentence").
    /// - Returns: JavaScript string to evaluate in WKWebView.
    static func initTTSJS(granularity: String) -> String {
        let escaped = FoliateJSEscaper.escapeForJSString(granularity)
        return "readerAPI.initTTS('\(escaped)')"
    }

    /// Generate JS to start speaking the current block.
    /// - Returns: JavaScript string to evaluate in WKWebView.
    static func startTTSJS() -> String {
        "readerAPI.tts.start()"
    }

    /// Generate JS to advance to the next TTS block.
    /// - Returns: JavaScript string to evaluate in WKWebView.
    static func nextTTSJS() -> String {
        "readerAPI.tts.next()"
    }

    /// Generate JS to go back to the previous TTS block.
    /// - Returns: JavaScript string to evaluate in WKWebView.
    static func prevTTSJS() -> String {
        "readerAPI.tts.prev()"
    }

    /// Generate JS to highlight a word mark in the Foliate-js overlay.
    /// - Parameter mark: The mark name (numeric string from Intl.Segmenter).
    /// - Returns: JavaScript string to evaluate in WKWebView.
    static func setMarkJS(mark: String) -> String {
        let escaped = FoliateJSEscaper.escapeForJSString(mark)
        return "readerAPI.tts.setMark('\(escaped)')"
    }

    /// Parse a TTS text block from a JS `tts-text` message body.
    /// Extracts plain text and word boundary marks from the payload.
    /// - Parameter body: Raw message body (Any) from WKScriptMessage.
    /// - Returns: Parsed block, or nil if the payload is invalid.
    static func parseTTSBlock(_ body: Any) -> FoliateTTSBlock? {
        guard let dict = body as? [String: Any] else { return nil }
        guard let text = dict["text"] as? String else { return nil }

        let marksArray = dict["marks"] as? [[String: Any]] ?? []
        let marks = marksArray.compactMap(parseMark)

        return FoliateTTSBlock(text: text, marks: marks)
    }

    // MARK: - Private Helpers

    // Note: prior in-file `escapeForJS` removed in favor of the shared
    // `FoliateJSEscaper.escapeForJSString` (single source of truth, also
    // covers `\t`, U+2028, U+2029 — see bug #135 for the EPUB-side fix
    // that established this pattern). Inputs to `initTTSJS` and
    // `setMarkJS` are constrained today, so this is consolidation rather
    // than an active vulnerability fix.

    /// Parse a single mark dictionary into a FoliateTTSMark.
    /// Returns nil if any required field is missing or has wrong type.
    private static func parseMark(_ dict: [String: Any]) -> FoliateTTSMark? {
        guard let name = dict["name"] as? String else { return nil }
        guard let start = dict["start"] as? Int else { return nil }
        guard let end = dict["end"] as? Int else { return nil }
        return FoliateTTSMark(name: name, start: start, end: end)
    }
}
