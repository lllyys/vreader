// Purpose: Tests for ReplacementTransform — content replacement rules.
// Validates string/regex replacement, offset mapping, edge cases.

import Testing
import Foundation
@testable import vreader

@Suite("ReplacementTransform")
struct ReplacementTransformTests {

    @Test func replace_simpleString_replaced() {
        let rules = [ReplacementRuleDescriptor(pattern: "foo", replacement: "bar")]
        let transform = ReplacementTransform(rules: rules)
        let result = transform.transform(input: "hello foo world")
        #expect(result.text == "hello bar world")
    }

    @Test func replace_regex_groupCapture() {
        let rules = [ReplacementRuleDescriptor(
            pattern: "(\\w+)@(\\w+)",
            replacement: "$2/$1",
            isRegex: true
        )]
        let transform = ReplacementTransform(rules: rules)
        let result = transform.transform(input: "user@domain")
        #expect(result.text == "domain/user")
    }

    @Test func replace_multipleRules_appliedInOrder() {
        let rules = [
            ReplacementRuleDescriptor(pattern: "aaa", replacement: "b", order: 0),
            ReplacementRuleDescriptor(pattern: "b", replacement: "cc", order: 1),
        ]
        let transform = ReplacementTransform(rules: rules)
        let result = transform.transform(input: "aaa")
        // First: "aaa" -> "b", Second: "b" -> "cc"
        #expect(result.text == "cc")
    }

    @Test func replace_noMatch_unchanged() {
        let rules = [ReplacementRuleDescriptor(pattern: "xyz", replacement: "abc")]
        let transform = ReplacementTransform(rules: rules)
        let result = transform.transform(input: "hello world")
        #expect(result.text == "hello world")
    }

    @Test func replace_emptyPattern_noOp() {
        let rules = [ReplacementRuleDescriptor(pattern: "", replacement: "abc")]
        let transform = ReplacementTransform(rules: rules)
        let result = transform.transform(input: "hello")
        #expect(result.text == "hello")
    }

    @Test func replace_invalidRegex_skipped() {
        let rules = [ReplacementRuleDescriptor(
            pattern: "[invalid(regex",
            replacement: "x",
            isRegex: true
        )]
        let transform = ReplacementTransform(rules: rules)
        let result = transform.transform(input: "hello world")
        #expect(result.text == "hello world")
    }

    @Test func replace_disabledRule_skipped() {
        let rules = [ReplacementRuleDescriptor(
            pattern: "hello",
            replacement: "bye",
            enabled: false
        )]
        let transform = ReplacementTransform(rules: rules)
        let result = transform.transform(input: "hello world")
        #expect(result.text == "hello world")
    }

    @Test func offsetMap_afterReplacement_correct() {
        // Replace "ab" with "X" in "xxabxx"
        // Source: "xxabxx" (6 UTF-16) -> Display: "xxXxx" (5 UTF-16)
        let rules = [ReplacementRuleDescriptor(pattern: "ab", replacement: "X")]
        let transform = ReplacementTransform(rules: rules)
        let result = transform.transform(input: "xxabxx")
        #expect(result.text == "xxXxx")
        #expect(result.offsetMap.sourceLengthUTF16 == 6)
        #expect(result.offsetMap.displayLengthUTF16 == 5)
        // Offset 0 -> 0 (before replacement)
        #expect(result.offsetMap.sourceToDisplay(0) == 0)
        // Offset 2 -> 2 (start of "ab" -> start of "X")
        #expect(result.offsetMap.sourceToDisplay(2) == 2)
        // Offset 4 -> 3 (after "ab" in source -> after "X" in display)
        #expect(result.offsetMap.sourceToDisplay(4) == 3)
    }

    @Test func cjkCharacters_correct() {
        let rules = [ReplacementRuleDescriptor(pattern: "水印", replacement: "")]
        let transform = ReplacementTransform(rules: rules)
        let result = transform.transform(input: "这是水印文字")
        #expect(result.text == "这是文字")
    }

    @Test func regex_multipleMatches() {
        let rules = [ReplacementRuleDescriptor(
            pattern: "\\d+",
            replacement: "#",
            isRegex: true
        )]
        let transform = ReplacementTransform(rules: rules)
        let result = transform.transform(input: "page 1 of 100")
        #expect(result.text == "page # of #")
    }

    // Opt-in only — set VREADER_RUN_CONTENTION_TESTS=1 to run it. This is the
    // deterministic RED that proved Bug #217: it fails on the pre-fix commit
    // (the regex rule no-op'd) and passes after the fix. It is gated out of
    // normal runs because it CPU-saturates DispatchQueue.global() for ~1.6s —
    // no QoS setting can both starve the default-QoS pool the buggy code used
    // and spare neighbours — which would slow parallel tests and could perturb
    // wall-clock assertions such as
    // SimpTradTransformTests.performance_1MBText_under500ms.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["VREADER_RUN_CONTENTION_TESTS"] == "1"))
    func regexRule_appliesUnderGlobalQueueContention() {
        // Bug #217 regression: applyRegexRule used to run the match on
        // DispatchQueue.global() and block on a 1s DispatchSemaphore. When the
        // global queue was saturated, the work item could not get a thread
        // within the window, the wait spuriously timed out, and the rule
        // silently no-op'd (returned the input unchanged). CPU-saturate the
        // global queue for longer than that old 1s timeout, then confirm the
        // regex rule STILL applies — the fixed code matches synchronously on
        // the calling thread and has no dependency on the dispatch pool.
        let deadline = Date().addingTimeInterval(1.6)
        let spinnerCount = ProcessInfo.processInfo.activeProcessorCount * 4
        let group = DispatchGroup()
        for _ in 0..<spinnerCount {
            group.enter()
            DispatchQueue.global().async {
                while Date() < deadline { /* CPU-bound spin holds a pool thread */ }
                group.leave()
            }
        }
        defer { group.wait() }  // drain spinners so the pool is not left saturated

        let rules = [ReplacementRuleDescriptor(
            pattern: "\\d+",
            replacement: "#",
            isRegex: true
        )]
        let result = ReplacementTransform(rules: rules).transform(input: "page 1 of 100")
        #expect(result.text == "page # of #",
                "Bug #217: regex replacement must apply even when DispatchQueue.global() is saturated")
    }

    @Test func emptyInput_noOp() {
        let rules = [ReplacementRuleDescriptor(pattern: "x", replacement: "y")]
        let transform = ReplacementTransform(rules: rules)
        let result = transform.transform(input: "")
        #expect(result.text == "")
        #expect(result.offsetMap.sourceLengthUTF16 == 0)
    }

    @Test func noRules_identity() {
        let transform = ReplacementTransform(rules: [])
        let result = transform.transform(input: "hello")
        #expect(result.text == "hello")
    }

    @Test func replacement_deletion_emptyReplacement() {
        let rules = [ReplacementRuleDescriptor(pattern: "remove_me", replacement: "")]
        let transform = ReplacementTransform(rules: rules)
        let result = transform.transform(input: "keep remove_me this")
        #expect(result.text == "keep  this")
    }

    @Test func replacement_expansion_longerReplacement() {
        let rules = [ReplacementRuleDescriptor(pattern: "a", replacement: "AAA")]
        let transform = ReplacementTransform(rules: rules)
        let result = transform.transform(input: "ab")
        #expect(result.text == "AAAb")
        #expect(result.offsetMap.sourceToDisplay(0) == 0) // start of 'a'
        #expect(result.offsetMap.sourceToDisplay(1) == 3) // 'b' shifts
    }
}
