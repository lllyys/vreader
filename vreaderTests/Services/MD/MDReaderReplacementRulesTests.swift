// Purpose: Tests for feature #54 WI-7 — content replacement rules in the
// native Markdown reader. Verifies `MDFileLoader.load` applies a
// `ReplacementTransform` (and composes it with the existing
// `SimpTradTransform`) to the decoded SOURCE text BEFORE `parser.parse`.
//
// @coordinates-with: MDFileLoader.swift, ReplacementTransform.swift,
//   SimpTradTransform.swift, TextMapper.swift, MockMDParser.swift

import Testing
import Foundation
@testable import vreader

@Suite("MDReaderReplacementRules — feature #54 WI-7")
struct MDReaderReplacementRulesTests {

    // MARK: - Fixtures

    private static let fp = DocumentFingerprint(
        contentSHA256: "md_replrules_test_sha256_000000000000000000000000000000000",
        fileByteCount: 200,
        format: .md
    )

    /// Writes `source` to a temp .md file and returns the URL. Caller defers cleanup.
    private func writeTempMD(_ source: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("md_replrules_\(UUID().uuidString).md")
        try source.data(using: .utf8)!.write(to: url)
        return url
    }

    // MARK: - Plain-string rule applies before parse

    @Test("a plain-string replacement rule is applied to the source before parse")
    func plainStringRuleAppliedBeforeParse() async throws {
        let parser = MockMDParser()
        let store = MockPositionStore()
        let source = "# Heading\n\nThe quick brown fox.\n"
        let url = try writeTempMD(source)
        defer { try? FileManager.default.removeItem(at: url) }

        let rule = ReplacementRuleDescriptor(
            pattern: "brown", replacement: "red", isRegex: false, enabled: true, order: 0
        )

        _ = try await MDFileLoader.load(
            url: url,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: Self.fp.canonicalKey,
            replacementRules: [rule]
        )

        // The parser must have received the post-transform source.
        let parsed = try #require(parser.lastParsedText)
        #expect(parsed.contains("red"))
        #expect(!parsed.contains("brown"))
        #expect(parsed.contains("The quick red fox."))
    }

    // MARK: - Regex rule applies before parse

    @Test("a regex replacement rule is applied to the source before parse")
    func regexRuleAppliedBeforeParse() async throws {
        let parser = MockMDParser()
        let store = MockPositionStore()
        let source = "Order 123 and order 456.\n"
        let url = try writeTempMD(source)
        defer { try? FileManager.default.removeItem(at: url) }

        // Replace any run of digits with "#".
        let rule = ReplacementRuleDescriptor(
            pattern: "[0-9]+", replacement: "#", isRegex: true, enabled: true, order: 0
        )

        _ = try await MDFileLoader.load(
            url: url,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: Self.fp.canonicalKey,
            replacementRules: [rule]
        )

        let parsed = try #require(parser.lastParsedText)
        #expect(parsed.contains("Order # and order #."))
        #expect(!parsed.contains("123"))
        #expect(!parsed.contains("456"))
    }

    // MARK: - No rules → identity passthrough

    @Test("no replacement rules leaves the source text unchanged")
    func noRulesIdentityPassthrough() async throws {
        let parser = MockMDParser()
        let store = MockPositionStore()
        let source = "# Title\n\nUnchanged body text.\n"
        let url = try writeTempMD(source)
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try await MDFileLoader.load(
            url: url,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: Self.fp.canonicalKey,
            replacementRules: []
        )

        // Identity: parser sees the source byte-for-byte.
        #expect(parser.lastParsedText == source)
    }

    @Test("omitting the replacementRules argument is an identity passthrough")
    func omittedArgumentIsIdentity() async throws {
        // Backward-compat: existing call sites that don't pass the new
        // argument must behave exactly as before.
        let parser = MockMDParser()
        let store = MockPositionStore()
        let source = "# Compat\n\nLegacy call site.\n"
        let url = try writeTempMD(source)
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try await MDFileLoader.load(
            url: url,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: Self.fp.canonicalKey
        )

        #expect(parser.lastParsedText == source)
    }

    // MARK: - Disabled rule is skipped

    @Test("a disabled replacement rule is not applied")
    func disabledRuleSkipped() async throws {
        let parser = MockMDParser()
        let store = MockPositionStore()
        let source = "Keep the watermark here.\n"
        let url = try writeTempMD(source)
        defer { try? FileManager.default.removeItem(at: url) }

        let rule = ReplacementRuleDescriptor(
            pattern: "watermark", replacement: "REDACTED", isRegex: false,
            enabled: false, order: 0
        )

        _ = try await MDFileLoader.load(
            url: url,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: Self.fp.canonicalKey,
            replacementRules: [rule]
        )

        // enabled == false → rule is a no-op; source reaches the parser intact.
        #expect(parser.lastParsedText == source)
    }

    // MARK: - Rule ordering

    @Test("replacement rules apply in `order` sequence")
    func rulesApplyInOrder() async throws {
        let parser = MockMDParser()
        let store = MockPositionStore()
        let source = "aaa\n"
        let url = try writeTempMD(source)
        defer { try? FileManager.default.removeItem(at: url) }

        // order 0: a → b  ⇒ "bbb"; order 1: b → c ⇒ "ccc".
        let r0 = ReplacementRuleDescriptor(pattern: "a", replacement: "b", order: 0)
        let r1 = ReplacementRuleDescriptor(pattern: "b", replacement: "c", order: 1)

        _ = try await MDFileLoader.load(
            url: url,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: Self.fp.canonicalKey,
            // Pass out of order — `ReplacementTransform` sorts by `order`.
            replacementRules: [r1, r0]
        )

        #expect(parser.lastParsedText == "ccc\n")
    }

    // MARK: - Composition with Chinese conversion

    @Test("replacement rules apply before Chinese conversion — order is provable")
    func composesWithChineseConversion() async throws {
        let parser = MockMDParser()
        let store = MockPositionStore()
        // The source carries the SIMPLIFIED token 测试.
        let source = "这是测试文本\n"
        let url = try writeTempMD(source)
        defer { try? FileManager.default.removeItem(at: url) }

        // Replacement rule matches the SIMPLIFIED form 测试 → 检测.
        // Chain order MUST be replacement-then-conversion:
        //   correct order:  测试 →(rule)→ 检测 →(s2t)→ 檢測   ✓ match
        //   flipped order:  测试 →(s2t)→ 測試 ... rule no longer matches  ✗
        // so a passing assertion only holds for replacement-before-conversion.
        let rule = ReplacementRuleDescriptor(
            pattern: "测试", replacement: "检测", isRegex: false, enabled: true, order: 0
        )

        _ = try await MDFileLoader.load(
            url: url,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: Self.fp.canonicalKey,
            renderConfig: .default,
            chineseConversion: .simpToTrad,
            replacementRules: [rule]
        )

        let parsed = try #require(parser.lastParsedText)
        // Rule applied first (测试→检测), then s2t converted everything:
        // 这→這, 检测→檢測, 文本 unchanged.
        #expect(parsed.contains("檢測"))
        #expect(!parsed.contains("测试"))   // simplified rule pattern gone
        #expect(!parsed.contains("測試"))   // would appear if s2t ran first
        #expect(!parsed.contains("检测"))   // pre-conversion replacement output gone
        #expect(parsed.contains("這"))      // 这 → 這 confirms s2t also ran
    }

    // MARK: - Corrupt regex is skipped, not fatal

    @Test("a corrupt regex rule is skipped without crashing the load")
    func corruptRegexRuleSkipped() async throws {
        let parser = MockMDParser()
        let store = MockPositionStore()
        let source = "Body text survives.\n"
        let url = try writeTempMD(source)
        defer { try? FileManager.default.removeItem(at: url) }

        // "[" is an invalid regex (unclosed character class).
        let badRule = ReplacementRuleDescriptor(
            pattern: "[", replacement: "X", isRegex: true, enabled: true, order: 0
        )
        // A valid rule alongside it must still apply.
        let goodRule = ReplacementRuleDescriptor(
            pattern: "survives", replacement: "remains", isRegex: false, enabled: true, order: 1
        )

        let result = try await MDFileLoader.load(
            url: url,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: Self.fp.canonicalKey,
            replacementRules: [badRule, goodRule]
        )

        // Load did not throw; the bad rule was a no-op; the good rule applied.
        let parsed = try #require(parser.lastParsedText)
        #expect(parsed.contains("Body text remains."))
        #expect(result.documentInfo.renderedText.contains("remains"))
    }

    // MARK: - Restored offset clamps to post-transform rendered length

    @Test("restored offset clamps to the post-transform rendered text length")
    func restoredOffsetClampsToPostTransformLength() async throws {
        let parser = MockMDParser()
        let store = MockPositionStore()
        // A length-shrinking rule: "longword" (8) → "x" (1).
        let source = "longword longword longword\n"
        let url = try writeTempMD(source)
        defer { try? FileManager.default.removeItem(at: url) }

        let rule = ReplacementRuleDescriptor(
            pattern: "longword", replacement: "x", isRegex: false, enabled: true, order: 0
        )
        // Saved offset is past the post-transform length ("x x x\n" == 6 UTF-16).
        let savedLocator = Locator(
            bookFingerprint: Self.fp,
            href: nil, progression: nil, totalProgression: 0.99,
            cfi: nil, page: nil,
            charOffsetUTF16: 500,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        await store.seed(bookFingerprintKey: Self.fp.canonicalKey, locator: savedLocator)

        let result = try await MDFileLoader.load(
            url: url,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: Self.fp.canonicalKey,
            replacementRules: [rule]
        )

        let parsed = try #require(parser.lastParsedText)
        let renderedLen = result.documentInfo.renderedTextLengthUTF16
        #expect(parsed == "x x x\n")
        // The clamp uses the rendered length the post-transform parse produced.
        #expect(result.restoredOffsetUTF16 == renderedLen)
        #expect(result.restoredOffsetUTF16 <= renderedLen)
    }
}
