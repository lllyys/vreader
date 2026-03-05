// Purpose: Fixture-based tests for EncodingDetector using actual test files.

import Testing
import Foundation
@testable import vreader

@Suite("EncodingDetector Fixtures")
struct EncodingFixtureTests {

    /// Helper to load fixture data from the test bundle.
    private func fixtureData(named filename: String) throws -> Data {
        // When running via Xcode test runner, fixtures are in the test bundle.
        // When fixtures are not accessible via bundle, we fall back to relative path.
        let bundlePath = Bundle(for: BundleToken.self).resourcePath ?? ""
        let bundleURL = URL(fileURLWithPath: bundlePath)
            .appendingPathComponent("Encoding")
            .appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: bundleURL.path) {
            return try Data(contentsOf: bundleURL)
        }

        // Fallback: direct path from project root
        let directURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent(filename)
        return try Data(contentsOf: directURL)
    }

    // MARK: - UTF-8 BOM Fixture

    @Test func utf8BOMFixture() throws {
        let data = try fixtureData(named: "utf8_bom.txt")
        let result = try EncodingDetector.detect(data: data)
        #expect(result.encoding == .utf8)
        #expect(result.text.contains("Hello UTF-8 BOM"))
    }

    // MARK: - UTF-16 LE BOM Fixture

    @Test func utf16LEBOMFixture() throws {
        let data = try fixtureData(named: "utf16le_bom.txt")
        let result = try EncodingDetector.detect(data: data)
        #expect(result.encoding == .utf16LittleEndian)
        #expect(result.text.contains("Hello"))
    }

    // MARK: - UTF-16 BE BOM Fixture

    @Test func utf16BEBOMFixture() throws {
        let data = try fixtureData(named: "utf16be_bom.txt")
        let result = try EncodingDetector.detect(data: data)
        #expect(result.encoding == .utf16BigEndian)
        #expect(result.text.contains("Hello"))
    }

    // MARK: - Plain UTF-8 Fixture

    @Test func plainUTF8Fixture() throws {
        let data = try fixtureData(named: "plain_utf8.txt")
        let result = try EncodingDetector.detect(data: data)
        #expect(result.encoding == .utf8)
        #expect(result.text == "Hello, plain UTF-8 text.")
    }

    // MARK: - Empty File Fixture

    @Test func emptyFileFixture() throws {
        let data = try fixtureData(named: "empty.txt")
        let result = try EncodingDetector.detect(data: data)
        #expect(result.text.isEmpty)
        #expect(result.encoding == .utf8)
    }

    // MARK: - Binary Masquerade Fixture

    @Test func binaryMasqueradeFixture() throws {
        let data = try fixtureData(named: "binary_masquerade.txt")
        do {
            _ = try EncodingDetector.detect(data: data)
            Issue.record("Expected binaryMasquerade error")
        } catch let error as ImportError {
            #expect(error == .binaryMasquerade)
        }
    }
}

/// Dummy class for bundle lookup in test target.
private final class BundleToken {}
