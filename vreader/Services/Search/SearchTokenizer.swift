// Purpose: Text tokenizer for search indexing — splits text into tokens with UTF-16 offsets.
// Used by SearchIndexStore to build the token span map.
//
// Key decisions:
// - Splits on non-alphanumeric boundaries (whitespace, punctuation).
// - Each token is normalized via SearchTextNormalizer.
// - Returns UTF-16 code unit offsets matching NSString/UITextView semantics.
// - Handles surrogate pairs correctly by operating on UTF16View indices.
//
// @coordinates-with SearchIndexStore.swift, SearchTextNormalizer.swift

import Foundation

/// A token with its normalized form and UTF-16 position in the source text.
struct IndexedToken: Sendable {
    let normalized: String
    let startUTF16: Int
    let endUTF16: Int
}

/// Tokenizes text for search indexing with UTF-16 offset tracking.
enum SearchTokenizer {

    /// Splits text into tokens with normalized forms and UTF-16 offsets.
    static func tokenize(_ text: String) -> [IndexedToken] {
        var tokens: [IndexedToken] = []
        let utf16 = text.utf16
        var i = utf16.startIndex
        let end = utf16.endIndex

        while i < end {
            // Skip non-alphanumeric
            guard CharacterSet.alphanumerics.contains(
                Unicode.Scalar(utf16[i]) ?? Unicode.Scalar(0)
            ) else {
                i = utf16.index(after: i)
                continue
            }

            let tokenStart = utf16.distance(from: utf16.startIndex, to: i)
            var j = i

            // Consume alphanumeric characters
            while j < end,
                  let scalar = Unicode.Scalar(utf16[j]),
                  CharacterSet.alphanumerics.contains(scalar) {
                j = utf16.index(after: j)
            }

            let tokenEnd = utf16.distance(from: utf16.startIndex, to: j)
            let startIdx = String.Index(utf16Offset: tokenStart, in: text)
            let endIdx = String.Index(utf16Offset: tokenEnd, in: text)
            let tokenText = String(text[startIdx..<endIdx])
            let normalized = SearchTextNormalizer.normalize(tokenText)

            if !normalized.isEmpty {
                tokens.append(IndexedToken(
                    normalized: normalized,
                    startUTF16: tokenStart,
                    endUTF16: tokenEnd
                ))
            }
            i = j
        }

        return tokens
    }

    /// Escapes a query string for safe FTS5 MATCH usage.
    /// Wraps each token in double quotes for literal matching.
    /// Embedded double quotes are escaped as "" per FTS5 spec.
    static func escapeFTS5Query(_ query: String) -> String {
        let tokens = query.split(separator: " ").map { token -> String in
            let escaped = token.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return tokens.joined(separator: " ")
    }
}
