// Purpose: Feature #68 WI-3 — tests that MDFileLoader.load forwards the
// `renderConfig` argument into `parser.parse`, replacing the previously
// hardcoded `MDRenderConfig.default`.
//
// @coordinates-with: MDFileLoader.swift, MockMDParser.swift

#if canImport(UIKit)
import Testing
import Foundation
import UIKit
@testable import vreader

@Suite("MDFileLoader — renderConfig plumbing (feature #68 WI-3)")
struct MDFileLoaderRenderConfigTests {

    private let testFP = DocumentFingerprint(
        contentSHA256: "md_loader_rc_test_sha256_000000000000000000000000000000000",
        fileByteCount: 200,
        format: .md
    )

    private func writeTempMD(_ source: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("md_rc_test_\(UUID().uuidString).md")
        try source.data(using: .utf8)!.write(to: url)
        return url
    }

    @Test("load with an explicit non-default renderConfig reaches parser.parse")
    func loadForwardsRenderConfig() async throws {
        let parser = MockMDParser()
        let store = MockPositionStore()
        let url = try writeTempMD("# Title\n\nBody.")
        defer { try? FileManager.default.removeItem(at: url) }

        var custom = MDRenderConfig.default
        custom.fontSize = 31
        custom.accentColor = UIColor(red: 0.55, green: 0.18, blue: 0.18, alpha: 1.0)

        _ = try await MDFileLoader.load(
            url: url,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey,
            renderConfig: custom
        )

        // The mock records the config it received — it must be the custom
        // one, not a hardcoded .default.
        #expect(parser.lastParsedConfig?.fontSize == 31)
        #expect(parser.lastParsedConfig?.accentColor == custom.accentColor)
    }

    @Test("load without a renderConfig argument uses .default (back-compat)")
    func loadDefaultsRenderConfig() async throws {
        let parser = MockMDParser()
        let store = MockPositionStore()
        let url = try writeTempMD("# Title\n\nBody.")
        defer { try? FileManager.default.removeItem(at: url) }

        _ = try await MDFileLoader.load(
            url: url,
            parser: parser,
            positionStore: store,
            bookFingerprintKey: testFP.canonicalKey
        )

        #expect(parser.lastParsedConfig == MDRenderConfig.default)
    }
}
#endif
