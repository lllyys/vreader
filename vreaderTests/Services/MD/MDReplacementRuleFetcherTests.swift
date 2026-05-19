// Purpose: SwiftData-backed tests for MDReplacementRuleFetcher — verifies
// the scoped fetch (feature #54 WI-7): enabled rows only, global +
// book-scoped rows selected, other-book rows excluded, `order` sorting,
// and the nil-container fallback.
//
// @coordinates-with: MDReplacementRuleFetcher.swift,
//   ContentReplacementRule.swift

import Testing
import Foundation
import SwiftData
@testable import vreader

@Suite("MDReplacementRuleFetcher — feature #54 WI-7")
struct MDReplacementRuleFetcherTests {

    private let bookKey = "md:replrulefetcher000000000000000000000000000000000000000000:100"
    private let otherBookKey = "md:replrulefetcher111111111111111111111111111111111111111111:200"

    /// Fresh in-memory SchemaV6 container + context per test.
    private func makeContext() throws -> ModelContext {
        let container = try CollectionTestHelper.makeContainer()
        return ModelContext(container)
    }

    private func insert(
        into ctx: ModelContext,
        pattern: String,
        replacement: String,
        scopeKey: String,
        enabled: Bool = true,
        order: Int = 0,
        isRegex: Bool = false
    ) {
        ctx.insert(ContentReplacementRule(
            pattern: pattern,
            replacement: replacement,
            isRegex: isRegex,
            scopeKey: scopeKey,
            enabled: enabled,
            order: order
        ))
    }

    // MARK: - nil container fallback

    @Test("nil container yields an empty rule list")
    func nilContainerYieldsEmpty() async {
        let rules = await MDReplacementRuleFetcher.rules(container: nil, bookKey: bookKey)
        #expect(rules.isEmpty)
    }

    // MARK: - Scope selection

    @Test("global rules are selected for any book")
    func globalRulesSelected() throws {
        let ctx = try makeContext()
        insert(into: ctx, pattern: "a", replacement: "b", scopeKey: "")
        try ctx.save()

        let rules = MDReplacementRuleFetcher.descriptors(context: ctx, bookKey: bookKey)
        #expect(rules.count == 1)
        #expect(rules.first?.pattern == "a")
    }

    @Test("a rule scoped to this book is selected")
    func bookScopedRuleSelected() throws {
        let ctx = try makeContext()
        insert(into: ctx, pattern: "x", replacement: "y", scopeKey: bookKey)
        try ctx.save()

        let rules = MDReplacementRuleFetcher.descriptors(context: ctx, bookKey: bookKey)
        #expect(rules.count == 1)
        #expect(rules.first?.pattern == "x")
    }

    @Test("a rule scoped to a DIFFERENT book is excluded")
    func otherBookRuleExcluded() throws {
        let ctx = try makeContext()
        insert(into: ctx, pattern: "other", replacement: "z", scopeKey: otherBookKey)
        try ctx.save()

        let rules = MDReplacementRuleFetcher.descriptors(context: ctx, bookKey: bookKey)
        #expect(rules.isEmpty)
    }

    @Test("global + this-book rules are selected, other-book rules dropped")
    func mixedScopeSelection() throws {
        let ctx = try makeContext()
        insert(into: ctx, pattern: "global", replacement: "G", scopeKey: "", order: 0)
        insert(into: ctx, pattern: "mine", replacement: "M", scopeKey: bookKey, order: 1)
        insert(into: ctx, pattern: "theirs", replacement: "T", scopeKey: otherBookKey, order: 2)
        try ctx.save()

        let rules = MDReplacementRuleFetcher.descriptors(context: ctx, bookKey: bookKey)
        let patterns = rules.map(\.pattern)
        #expect(patterns == ["global", "mine"])
        #expect(!patterns.contains("theirs"))
    }

    // MARK: - Enabled filtering

    @Test("a disabled rule is excluded at the fetch layer")
    func disabledRuleExcluded() throws {
        let ctx = try makeContext()
        insert(into: ctx, pattern: "on", replacement: "1", scopeKey: "", enabled: true, order: 0)
        insert(into: ctx, pattern: "off", replacement: "0", scopeKey: "", enabled: false, order: 1)
        try ctx.save()

        let rules = MDReplacementRuleFetcher.descriptors(context: ctx, bookKey: bookKey)
        let patterns = rules.map(\.pattern)
        #expect(patterns == ["on"])
        #expect(!patterns.contains("off"))
    }

    @Test("a disabled book-scoped rule is also excluded")
    func disabledBookScopedRuleExcluded() throws {
        let ctx = try makeContext()
        insert(into: ctx, pattern: "mine-off", replacement: "X", scopeKey: bookKey, enabled: false)
        try ctx.save()

        let rules = MDReplacementRuleFetcher.descriptors(context: ctx, bookKey: bookKey)
        #expect(rules.isEmpty)
    }

    // MARK: - Ordering

    @Test("fetched rules are sorted by `order` ascending")
    func rulesSortedByOrder() throws {
        let ctx = try makeContext()
        // Insert out of order.
        insert(into: ctx, pattern: "third", replacement: "3", scopeKey: "", order: 30)
        insert(into: ctx, pattern: "first", replacement: "1", scopeKey: "", order: 10)
        insert(into: ctx, pattern: "second", replacement: "2", scopeKey: "", order: 20)
        try ctx.save()

        let rules = MDReplacementRuleFetcher.descriptors(context: ctx, bookKey: bookKey)
        #expect(rules.map(\.pattern) == ["first", "second", "third"])
        #expect(rules.map(\.order) == [10, 20, 30])
    }

    // MARK: - Field mapping fidelity

    @Test("descriptor mapping preserves pattern, replacement, isRegex, order")
    func descriptorMappingFidelity() throws {
        let ctx = try makeContext()
        insert(
            into: ctx,
            pattern: "[0-9]+", replacement: "#", scopeKey: bookKey,
            enabled: true, order: 7, isRegex: true
        )
        try ctx.save()

        let rules = MDReplacementRuleFetcher.descriptors(context: ctx, bookKey: bookKey)
        let rule = try #require(rules.first)
        #expect(rule.pattern == "[0-9]+")
        #expect(rule.replacement == "#")
        #expect(rule.isRegex == true)
        #expect(rule.order == 7)
        #expect(rule.enabled == true)
    }

    // MARK: - Empty store

    @Test("an empty rule table yields an empty list")
    func emptyStoreYieldsEmpty() throws {
        let ctx = try makeContext()
        let rules = MDReplacementRuleFetcher.descriptors(context: ctx, bookKey: bookKey)
        #expect(rules.isEmpty)
    }

    // MARK: - rules(container:) wrapper

    @Test("the container-based wrapper returns the same scoped result")
    func containerWrapperReturnsScopedResult() async throws {
        let container = try CollectionTestHelper.makeContainer()
        let ctx = ModelContext(container)
        insert(into: ctx, pattern: "wrapped", replacement: "W", scopeKey: bookKey)
        insert(into: ctx, pattern: "theirs", replacement: "T", scopeKey: otherBookKey)
        try ctx.save()

        let rules = await MDReplacementRuleFetcher.rules(container: container, bookKey: bookKey)
        #expect(rules.map(\.pattern) == ["wrapped"])
    }
}
