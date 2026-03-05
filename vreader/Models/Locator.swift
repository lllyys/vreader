// Purpose: Universal reading position/range within a book.
// Supports EPUB (href+progression+CFI), PDF (page), and TXT (UTF-16 offsets).
//
// Key decisions:
// - All fields optional except bookFingerprint — format determines which fields apply.
// - TXT offsets are UTF-16 code units over raw decoded source (before display transforms).
// - canonicalHash provides a stable hash for deduplication/sync keys.
// - Canonical JSON: sorted keys, omit nil, 6 decimal float precision, \n line endings.
// - Float values must be finite; NaN/infinity are rejected in canonical JSON.
// - Float formatting uses POSIX locale for deterministic output across devices.

import Foundation
import CryptoKit

/// Validation errors for Locator field values.
enum LocatorValidationError: Error, Sendable {
    case negativePageIndex
    case negativeUTF16Offset
    case invertedUTF16Range
    case nonFiniteProgression
}

/// Universal reading position or range within a document.
struct Locator: Codable, Hashable, Sendable {
    let bookFingerprint: DocumentFingerprint

    // EPUB fields
    let href: String?
    let progression: Double?
    let totalProgression: Double?
    let cfi: String?

    // PDF fields
    let page: Int?

    // TXT canonical UTF-16 offset fields
    let charOffsetUTF16: Int?
    let charRangeStartUTF16: Int?
    let charRangeEndUTF16: Int?

    // Quote anchors for reflow recovery
    let textQuote: String?
    let textContextBefore: String?
    let textContextAfter: String?

    // MARK: - Validation

    /// Validates field values. Returns nil for valid locators, or a validation error.
    func validate() -> LocatorValidationError? {
        if let page, page < 0 { return .negativePageIndex }
        if let charOffsetUTF16, charOffsetUTF16 < 0 { return .negativeUTF16Offset }
        if let charRangeStartUTF16, charRangeStartUTF16 < 0 { return .negativeUTF16Offset }
        if let charRangeEndUTF16, charRangeEndUTF16 < 0 { return .negativeUTF16Offset }
        if let start = charRangeStartUTF16, let end = charRangeEndUTF16, start > end {
            return .invertedUTF16Range
        }
        if let p = progression, !p.isFinite { return .nonFiniteProgression }
        if let tp = totalProgression, !tp.isFinite { return .nonFiniteProgression }
        return nil
    }

    /// Creates a validated Locator. Returns nil if validation fails.
    static func validated(
        bookFingerprint: DocumentFingerprint,
        href: String? = nil,
        progression: Double? = nil,
        totalProgression: Double? = nil,
        cfi: String? = nil,
        page: Int? = nil,
        charOffsetUTF16: Int? = nil,
        charRangeStartUTF16: Int? = nil,
        charRangeEndUTF16: Int? = nil,
        textQuote: String? = nil,
        textContextBefore: String? = nil,
        textContextAfter: String? = nil
    ) -> Locator? {
        let locator = Locator(
            bookFingerprint: bookFingerprint, href: href,
            progression: progression, totalProgression: totalProgression,
            cfi: cfi, page: page,
            charOffsetUTF16: charOffsetUTF16,
            charRangeStartUTF16: charRangeStartUTF16,
            charRangeEndUTF16: charRangeEndUTF16,
            textQuote: textQuote, textContextBefore: textContextBefore,
            textContextAfter: textContextAfter
        )
        if locator.validate() != nil { return nil }
        return locator
    }

    // MARK: - Canonical Hash

    /// SHA-256 hash of canonical JSON representation.
    var canonicalHash: String {
        let json = canonicalJSON()
        let digest = SHA256.hash(data: Data(json.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Canonical JSON

    /// Produces a canonical JSON string with sorted keys, nil omission,
    /// rounded floats, and normalized line endings.
    func canonicalJSON() -> String {
        var pairs: [(String, String)] = []

        // bookFingerprint is always present — inline its fields with prefix
        pairs.append(("bookFingerprint.contentSHA256", jsonQuoted(bookFingerprint.contentSHA256)))
        pairs.append(("bookFingerprint.fileByteCount", "\(bookFingerprint.fileByteCount)"))
        pairs.append(("bookFingerprint.format", jsonQuoted(bookFingerprint.format.rawValue)))

        if let cfi { pairs.append(("cfi", jsonQuoted(cfi))) }
        if let charOffsetUTF16 { pairs.append(("charOffsetUTF16", "\(charOffsetUTF16)")) }
        if let charRangeEndUTF16 { pairs.append(("charRangeEndUTF16", "\(charRangeEndUTF16)")) }
        if let charRangeStartUTF16 { pairs.append(("charRangeStartUTF16", "\(charRangeStartUTF16)")) }
        if let href { pairs.append(("href", jsonQuoted(href))) }
        if let page { pairs.append(("page", "\(page)")) }
        if let progression, progression.isFinite {
            pairs.append(("progression", roundedString(progression)))
        }
        if let textContextAfter { pairs.append(("textContextAfter", jsonQuoted(normalizeLineEndings(textContextAfter)))) }
        if let textContextBefore { pairs.append(("textContextBefore", jsonQuoted(normalizeLineEndings(textContextBefore)))) }
        if let textQuote { pairs.append(("textQuote", jsonQuoted(normalizeLineEndings(textQuote)))) }
        if let totalProgression, totalProgression.isFinite {
            pairs.append(("totalProgression", roundedString(totalProgression)))
        }

        // Explicitly sort by key for stability
        pairs.sort { $0.0 < $1.0 }
        let body = pairs.map { "\"\($0.0)\":\($0.1)" }.joined(separator: ",")
        return "{\(body)}"
    }

    // MARK: - Private Helpers

    /// JSON-escapes a string per RFC 8259, including all control characters.
    private func jsonQuoted(_ s: String) -> String {
        var result = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04x", scalar.value)
                } else {
                    result += String(scalar)
                }
            }
        }
        result += "\""
        return result
    }

    /// Cached formatter for locale-independent float formatting with 6 decimal places.
    private static let posixFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.minimumFractionDigits = 6
        f.maximumFractionDigits = 6
        f.numberStyle = .decimal
        f.groupingSeparator = ""
        return f
    }()

    /// Locale-independent float formatting with 6 decimal places.
    private func roundedString(_ value: Double) -> String {
        Self.posixFormatter.string(from: NSNumber(value: value)) ?? "0.000000"
    }

    private func normalizeLineEndings(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: "\n")
         .replacingOccurrences(of: "\r", with: "\n")
    }
}
