// Purpose: Tests for the Feature #77 `bilingual?action=…` DebugBridge command
// parse — the CU-free harness that drives interlinear bilingual mode (enable /
// disable / status) so the loading shimmer is verifiable without the setup-sheet
// + provider gates an automated run can't satisfy. Pure value-type parsing.

#if DEBUG

import XCTest
@testable import vreader

final class DebugCommandBilingualTests: XCTestCase {

    // MARK: - enable

    func test_parse_bilingualEnable_returnsEnableWithNilOptionals() throws {
        let url = URL(string: "vreader-debug://bilingual?action=enable")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .bilingual(action: .enable(lang: nil, granularity: nil)))
    }

    func test_parse_bilingualEnableWithLangAndGranularity_returnsBoth() throws {
        let url = URL(string: "vreader-debug://bilingual?action=enable&lang=zh-Hans&granularity=sentence")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(
            cmd,
            .bilingual(action: .enable(lang: "zh-Hans", granularity: "sentence"))
        )
    }

    func test_parse_bilingualEnableEmptyLang_treatedAsNil() throws {
        // Empty values are normalized to nil (keep the persisted/default setting).
        let url = URL(string: "vreader-debug://bilingual?action=enable&lang=&granularity=")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .bilingual(action: .enable(lang: nil, granularity: nil)))
    }

    // MARK: - disable

    func test_parse_bilingualDisable_returnsDisable() throws {
        let url = URL(string: "vreader-debug://bilingual?action=disable")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .bilingual(action: .disable))
    }

    // MARK: - status

    func test_parse_bilingualStatus_defaultsDest() throws {
        let url = URL(string: "vreader-debug://bilingual?action=status")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .bilingual(action: .status(dest: "bilingual-status.json")))
    }

    func test_parse_bilingualStatusWithDest_usesProvidedDest() throws {
        let url = URL(string: "vreader-debug://bilingual?action=status&dest=readium-bi.json")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .bilingual(action: .status(dest: "readium-bi.json")))
    }

    // MARK: - errors

    func test_parse_bilingualMissingAction_throwsMissingParam() {
        let url = URL(string: "vreader-debug://bilingual")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.missingParam(let name) = error else {
                XCTFail("expected missingParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "action")
        }
    }

    func test_parse_bilingualUnknownAction_throwsInvalidParam() {
        let url = URL(string: "vreader-debug://bilingual?action=toggle")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.invalidParam(let name, _) = error else {
                XCTFail("expected invalidParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "action")
        }
    }

    // Codex Gate-4 Medium: granularity is validated at the parser boundary so a
    // typo fails loud instead of silently falling back to the default.
    func test_parse_bilingualEnableInvalidGranularity_throwsInvalidParam() {
        let url = URL(string: "vreader-debug://bilingual?action=enable&granularity=word")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.invalidParam(let name, _) = error else {
                XCTFail("expected invalidParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "granularity")
        }
    }

    func test_parse_bilingualEnableParagraphGranularity_accepted() throws {
        let url = URL(string: "vreader-debug://bilingual?action=enable&granularity=paragraph")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .bilingual(action: .enable(lang: nil, granularity: "paragraph")))
    }

    // Codex Gate-4 Low: status `dest` honors the path-safe basename contract.
    func test_parse_bilingualStatusPathTraversalDest_throwsInvalidParam() {
        let url = URL(string: "vreader-debug://bilingual?action=status&dest=..%2Fescape")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.invalidParam(let name, _) = error else {
                XCTFail("expected invalidParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "dest")
        }
    }
}

#endif
