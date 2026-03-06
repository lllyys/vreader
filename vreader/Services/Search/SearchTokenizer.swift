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
    /// Uses Character-level iteration to correctly handle surrogate pairs (non-BMP).
    static func tokenize(_ text: String) -> [IndexedToken] {
        var tokens: [IndexedToken] = []
        var utf16Offset = 0
        var currentTokenStart: Int?
        var currentTokenChars: [Character] = []

        for char in text {
            let charUTF16Length = char.utf16.count
            let isAlphanumeric = char.isLetter || char.isNumber

            if isAlphanumeric {
                if currentTokenStart == nil {
                    currentTokenStart = utf16Offset
                }
                currentTokenChars.append(char)
            } else {
                if let start = currentTokenStart {
                    let tokenText = String(currentTokenChars)
                    let normalized = SearchTextNormalizer.normalize(tokenText)
                    if !normalized.isEmpty {
                        tokens.append(IndexedToken(
                            normalized: normalized,
                            startUTF16: start,
                            endUTF16: utf16Offset
                        ))
                    }
                    currentTokenStart = nil
                    currentTokenChars.removeAll()
                }
            }
            utf16Offset += charUTF16Length
        }

        // Flush trailing token
        if let start = currentTokenStart {
            let tokenText = String(currentTokenChars)
            let normalized = SearchTextNormalizer.normalize(tokenText)
            if !normalized.isEmpty {
                tokens.append(IndexedToken(
                    normalized: normalized,
                    startUTF16: start,
                    endUTF16: utf16Offset
                ))
            }
        }

        return tokens
    }

    /// Escapes a query string for safe FTS5 MATCH usage.
    /// Wraps each token in double quotes for literal matching.
    /// Embedded double quotes are escaped as "" per FTS5 spec.
    static func escapeFTS5Query(_ query: String) -> String {
        let tokens = query.split(omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            .map { token -> String in
                let escaped = token.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\""
            }
        return tokens.joined(separator: " ")
    }
}
