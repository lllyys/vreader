// Purpose: Tests for DebugSnapshot — semantic state JSON written by the
// vreader-debug://snapshot command (feature #44 DebugBridge). Verifies the
// stable JSON shape that automated tests and AI agents read back from the
// app container.

#if DEBUG

import XCTest
@testable import vreader

final class DebugSnapshotTests: XCTestCase {

    // MARK: - Shape

    func test_encode_includesAllRequiredKeys() throws {
        let snap = DebugSnapshot(
            schemaVersion: 1,
            ts: "2026-05-02T10:00:00Z",
            currentBookId: "book-123",
            format: "epub",
            position: "epubcfi(/6/4!/4/1:0)",
            theme: "dark",
            fontSize: 18,
            selection: nil,
            highlightCount: 3,
            renderPhase: "settled",
            lastError: nil,
            partial: nil
        )
        let dict = try encodeAsDictionary(snap)
        let expectedKeys: Set<String> = [
            "schemaVersion", "ts", "currentBookId", "format", "position",
            "theme", "fontSize", "selection", "highlightCount",
            "renderPhase", "lastError", "partial",
        ]
        XCTAssertEqual(Set(dict.keys), expectedKeys)
    }

    func test_encode_outputIsStableJSON_sortedKeys() throws {
        let snap = DebugSnapshot(
            schemaVersion: 1,
            ts: "2026-05-02T10:00:00Z",
            currentBookId: nil,
            format: nil,
            position: nil,
            theme: nil,
            fontSize: nil,
            selection: nil,
            highlightCount: 0,
            renderPhase: "idle",
            lastError: nil,
            partial: nil
        )
        let data = try DebugSnapshot.encoder.encode(snap)
        let json = String(decoding: data, as: UTF8.self)
        // Stable output requires sorted keys for deterministic byte-comparison
        // across runs and machines.
        let currentBookIdIdx = json.range(of: "\"currentBookId\"")?.lowerBound
        let formatIdx = json.range(of: "\"format\"")?.lowerBound
        let tsIdx = json.range(of: "\"ts\"")?.lowerBound
        XCTAssertNotNil(currentBookIdIdx)
        XCTAssertNotNil(formatIdx)
        XCTAssertNotNil(tsIdx)
        // alphabetical ordering: currentBookId < format < ts
        XCTAssertLessThan(currentBookIdIdx!, formatIdx!)
        XCTAssertLessThan(formatIdx!, tsIdx!)
    }

    // MARK: - Optional fields

    func test_encode_nilOptionalsRenderAsNullExplicitly() throws {
        let snap = DebugSnapshot(
            schemaVersion: 1,
            ts: "2026-05-02T10:00:00Z",
            currentBookId: nil,
            format: nil,
            position: nil,
            theme: nil,
            fontSize: nil,
            selection: nil,
            highlightCount: 0,
            renderPhase: "idle",
            lastError: nil,
            partial: nil
        )
        let dict = try encodeAsDictionary(snap)
        // Explicit nulls so the consumer can distinguish "absent" from "unknown".
        XCTAssertTrue(dict["currentBookId"] is NSNull)
        XCTAssertTrue(dict["format"] is NSNull)
        XCTAssertTrue(dict["position"] is NSNull)
        XCTAssertTrue(dict["theme"] is NSNull)
        XCTAssertTrue(dict["fontSize"] is NSNull)
        XCTAssertTrue(dict["selection"] is NSNull)
        XCTAssertTrue(dict["lastError"] is NSNull)
    }

    func test_encode_nonNilOptionalsRenderWithValues() throws {
        let snap = DebugSnapshot(
            schemaVersion: 1,
            ts: "2026-05-02T10:00:00Z",
            currentBookId: "uuid-1",
            format: "txt",
            position: "12345",
            theme: "light",
            fontSize: 16,
            selection: nil,
            highlightCount: 7,
            renderPhase: "settled",
            lastError: "nothing",
            partial: ["currentBookId"]
        )
        let dict = try encodeAsDictionary(snap)
        XCTAssertEqual(dict["currentBookId"] as? String, "uuid-1")
        XCTAssertEqual(dict["format"] as? String, "txt")
        XCTAssertEqual(dict["position"] as? String, "12345")
        XCTAssertEqual(dict["theme"] as? String, "light")
        XCTAssertEqual(dict["fontSize"] as? Int, 16)
        XCTAssertEqual(dict["highlightCount"] as? Int, 7)
        XCTAssertEqual(dict["renderPhase"] as? String, "settled")
        XCTAssertEqual(dict["lastError"] as? String, "nothing")
    }

    // MARK: - Selection sub-object

    func test_encode_selectionRendersAsNestedObject() throws {
        let selection = DebugSnapshot.SelectionInfo(text: "hello", startOffset: 100, endOffset: 105)
        let snap = DebugSnapshot(
            schemaVersion: 1,
            ts: "2026-05-02T10:00:00Z",
            currentBookId: "book",
            format: "epub",
            position: nil,
            theme: nil,
            fontSize: nil,
            selection: selection,
            highlightCount: 0,
            renderPhase: "settled",
            lastError: nil,
            partial: nil
        )
        let dict = try encodeAsDictionary(snap)
        let nested = dict["selection"] as? [String: Any]
        XCTAssertNotNil(nested, "selection should be a nested object")
        XCTAssertEqual(nested?["text"] as? String, "hello")
        XCTAssertEqual(nested?["startOffset"] as? Int, 100)
        XCTAssertEqual(nested?["endOffset"] as? Int, 105)
    }

    // MARK: - Round-trip

    func test_roundTrip_preservesAllFields() throws {
        let original = DebugSnapshot(
            schemaVersion: 1,
            ts: "2026-05-02T10:00:00Z",
            currentBookId: "uuid",
            format: "azw3",
            position: "epubcfi(/6/4)",
            theme: "dark",
            fontSize: 20,
            selection: .init(text: "world", startOffset: 0, endOffset: 5),
            highlightCount: 12,
            renderPhase: "settled",
            lastError: nil,
            partial: ["selection"]
        )
        let data = try DebugSnapshot.encoder.encode(original)
        let decoded = try JSONDecoder().decode(DebugSnapshot.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Helpers

    private func encodeAsDictionary(_ snap: DebugSnapshot) throws -> [String: Any] {
        let data = try DebugSnapshot.encoder.encode(snap)
        let any = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = any as? [String: Any] else {
            XCTFail("expected dictionary, got \(any)")
            return [:]
        }
        return dict
    }
}

#endif
