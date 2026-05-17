// Purpose: TextTransform conformance for content replacement rules.
// Applies a list of replacement rules (string or regex) in order,
// building an OffsetMap for bidirectional offset tracking.
//
// Key decisions:
// - Rules applied in order (sorted by `order` field).
// - Invalid regex patterns are skipped (logged, not crashed).
// - Regex matching is synchronous on the calling thread (Bug #217). The
//   prior DispatchQueue.global() + 1s-semaphore timeout was removed: it
//   misfired under dispatch-pool saturation and silently dropped the rule.
// - Replacements are non-recursive (a replacement's output is not
//   re-scanned by the same rule).
//
// @coordinates-with: TextTransform.swift, OffsetMap.swift,
//   ContentReplacementRule.swift

import Foundation

/// A lightweight rule descriptor for ReplacementTransform.
/// Decoupled from SwiftData so the transform is testable without persistence.
struct ReplacementRuleDescriptor: Sendable {
    let pattern: String
    let replacement: String
    let isRegex: Bool
    let enabled: Bool
    let order: Int

    init(pattern: String, replacement: String, isRegex: Bool = false,
         enabled: Bool = true, order: Int = 0) {
        self.pattern = pattern
        self.replacement = replacement
        self.isRegex = isRegex
        self.enabled = enabled
        self.order = order
    }
}

/// Text transform that applies content replacement rules.
struct ReplacementTransform: TextTransform {
    let rules: [ReplacementRuleDescriptor]

    func transform(input: String) -> TransformResult {
        let sortedRules = rules.filter(\.enabled).sorted { $0.order < $1.order }

        guard !sortedRules.isEmpty, !input.isEmpty else {
            return TransformResult(
                text: input,
                offsetMap: .identity(lengthUTF16: input.utf16.count)
            )
        }

        var currentText = input
        var composedMap: OffsetMap? = nil

        for rule in sortedRules {
            let result = applySingleRule(rule, to: currentText)
            if let existing = composedMap {
                composedMap = existing.compose(with: result.offsetMap)
            } else {
                composedMap = result.offsetMap
            }
            currentText = result.text
        }

        return TransformResult(
            text: currentText,
            offsetMap: composedMap ?? .identity(lengthUTF16: input.utf16.count)
        )
    }

    // MARK: - Private

    private func applySingleRule(_ rule: ReplacementRuleDescriptor, to text: String) -> TransformResult {
        guard !rule.pattern.isEmpty else {
            return TransformResult(text: text, offsetMap: .identity(lengthUTF16: text.utf16.count))
        }

        if rule.isRegex {
            return applyRegexRule(rule, to: text)
        } else {
            return applyStringRule(rule, to: text)
        }
    }

    private func applyStringRule(_ rule: ReplacementRuleDescriptor, to text: String) -> TransformResult {
        var entries: [OffsetEntry] = []
        var output = ""
        var sourceOffset = 0
        var displayOffset = 0

        let patternUTF16Len = rule.pattern.utf16.count
        let replacementUTF16Len = rule.replacement.utf16.count

        var remaining = text[text.startIndex...]

        while let range = remaining.range(of: rule.pattern) {
            // Copy text before match
            let before = remaining[remaining.startIndex..<range.lowerBound]
            let beforeUTF16 = String(before).utf16.count
            output += before
            sourceOffset += beforeUTF16
            displayOffset += beforeUTF16

            // Record the replacement
            entries.append(OffsetEntry(
                sourceOffset: sourceOffset,
                displayOffset: displayOffset,
                sourceLength: patternUTF16Len,
                displayLength: replacementUTF16Len
            ))
            output += rule.replacement
            sourceOffset += patternUTF16Len
            displayOffset += replacementUTF16Len

            remaining = remaining[range.upperBound...]
        }

        // Copy trailing text
        let trailing = String(remaining)
        output += trailing

        return TransformResult(
            text: output,
            offsetMap: OffsetMap(
                entries: entries,
                sourceLengthUTF16: text.utf16.count,
                displayLengthUTF16: output.utf16.count
            )
        )
    }

    private func applyRegexRule(_ rule: ReplacementRuleDescriptor, to text: String) -> TransformResult {
        let regex: NSRegularExpression
        do {
            regex = try NSRegularExpression(pattern: rule.pattern, options: [])
        } catch {
            // Invalid regex — skip this rule
            return TransformResult(text: text, offsetMap: .identity(lengthUTF16: text.utf16.count))
        }

        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        // Match synchronously on the calling thread. Bug #217: the previous
        // implementation dispatched this to DispatchQueue.global() and waited
        // on a 1s DispatchSemaphore — under dispatch-pool saturation the work
        // item could not get a thread within the window, the wait spuriously
        // timed out, and the rule silently no-op'd. The dispatch hop bought
        // nothing: matching a content-replacement pattern is microsecond-scale.
        let matches = regex.matches(in: text, options: [], range: fullRange)

        if matches.isEmpty {
            return TransformResult(text: text, offsetMap: .identity(lengthUTF16: text.utf16.count))
        }

        // Build output and offset entries
        var entries: [OffsetEntry] = []
        var output = ""
        var sourceOffset = 0
        var displayOffset = 0

        for match in matches {
            let matchRange = match.range
            let matchStart = matchRange.location
            let matchLen = matchRange.length

            // Copy text before match
            let beforeLen = matchStart - sourceOffset
            if beforeLen > 0 {
                let beforeRange = NSRange(location: sourceOffset, length: beforeLen)
                output += nsText.substring(with: beforeRange)
                displayOffset += beforeLen
            }
            sourceOffset = matchStart

            // Build replacement with group references
            let replacementText = regex.replacementString(
                for: match, in: text, offset: 0, template: rule.replacement
            )
            let replUTF16Len = (replacementText as NSString).length

            entries.append(OffsetEntry(
                sourceOffset: sourceOffset,
                displayOffset: displayOffset,
                sourceLength: matchLen,
                displayLength: replUTF16Len
            ))

            output += replacementText
            sourceOffset += matchLen
            displayOffset += replUTF16Len
        }

        // Copy trailing text
        let trailingLen = nsText.length - sourceOffset
        if trailingLen > 0 {
            output += nsText.substring(with: NSRange(location: sourceOffset, length: trailingLen))
        }

        return TransformResult(
            text: output,
            offsetMap: OffsetMap(
                entries: entries,
                sourceLengthUTF16: nsText.length,
                displayLengthUTF16: (output as NSString).length
            )
        )
    }
}
