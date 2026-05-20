// Purpose: Tests for DebugCommand parser — URL grammar for the vreader-debug://
// scheme used by feature #44 DebugBridge. Pure value-type parsing, no OS deps.

#if DEBUG

import XCTest
@testable import vreader

final class DebugCommandTests: XCTestCase {

    // MARK: - reset

    func test_parse_reset_returnsResetCommand() throws {
        let url = URL(string: "vreader-debug://reset")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .reset)
    }

    func test_parse_resetWithTrailingSlash_returnsResetCommand() throws {
        let url = URL(string: "vreader-debug://reset/")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .reset)
    }

    // MARK: - seed

    func test_parse_seedWithFixture_returnsSeed() throws {
        let url = URL(string: "vreader-debug://seed?fixture=alice")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .seed(fixture: "alice"))
    }

    func test_parse_seedMissingFixture_throwsMissingParam() {
        let url = URL(string: "vreader-debug://seed")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.missingParam(let name) = error else {
                XCTFail("expected missingParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "fixture")
        }
    }

    func test_parse_seedEmptyFixtureValue_throwsMissingParam() {
        let url = URL(string: "vreader-debug://seed?fixture=")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.missingParam(let name) = error else {
                XCTFail("expected missingParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "fixture")
        }
    }

    // MARK: - open

    func test_parse_openWithBookIdAndCFI_returnsOpen() throws {
        let bookId = "550e8400-e29b-41d4-a716-446655440000"
        let cfi = "epubcfi(/6/4!/4/1:0)"
        let encodedCFI = cfi.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "vreader-debug://open?bookId=\(bookId)&position=\(encodedCFI)")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .open(bookId: bookId, position: cfi))
    }

    func test_parse_openWithBookIdOnly_returnsOpenWithNilPosition() throws {
        let bookId = "550e8400-e29b-41d4-a716-446655440000"
        let url = URL(string: "vreader-debug://open?bookId=\(bookId)")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .open(bookId: bookId, position: nil))
    }

    // MARK: - feature #49 WI-0 grammar reconciliation

    func test_parse_openWithLegacyCFIParam_throwsInvalidParam() {
        // The legacy `cfi=` parameter was renamed to `position=` in feature
        // #49's grammar-reconciliation WI. Any caller still using `cfi` must
        // get a clear error rather than silently opening at the start —
        // otherwise verification flows that pass `cfi=...` would think the
        // open succeeded when actually the position was dropped.
        let bookId = "550e8400-e29b-41d4-a716-446655440000"
        let url = URL(string: "vreader-debug://open?bookId=\(bookId)&cfi=foo")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.invalidParam(let name, _) = error else {
                XCTFail("expected invalidParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "cfi")
        }
    }

    func test_parse_openWithCFIAndPosition_throwsInvalidParam() {
        // If both `cfi` and `position` are supplied, the legacy `cfi` still
        // takes precedence as the rejection — caller must remove `cfi`.
        let bookId = "550e8400-e29b-41d4-a716-446655440000"
        let url = URL(string: "vreader-debug://open?bookId=\(bookId)&cfi=foo&position=bar")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.invalidParam(let name, _) = error else {
                XCTFail("expected invalidParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "cfi")
        }
    }

    func test_parse_openMissingBookId_throwsMissingParam() {
        let url = URL(string: "vreader-debug://open")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.missingParam(let name) = error else {
                XCTFail("expected missingParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "bookId")
        }
    }

    // MARK: - theme

    func test_parse_themeDarkWithFontSize_returnsTheme() throws {
        let url = URL(string: "vreader-debug://theme?mode=dark&fontSize=18")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .theme(mode: .dark, fontSize: 18))
    }

    func test_parse_themeLightModeOnly_returnsThemeWithNilFontSize() throws {
        let url = URL(string: "vreader-debug://theme?mode=light")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .theme(mode: .light, fontSize: nil))
    }

    func test_parse_themeUnknownMode_throwsInvalidParam() {
        let url = URL(string: "vreader-debug://theme?mode=neon")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.invalidParam(let name, _) = error else {
                XCTFail("expected invalidParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "mode")
        }
    }

    func test_parse_themeNonNumericFontSize_throwsInvalidParam() {
        let url = URL(string: "vreader-debug://theme?mode=dark&fontSize=huge")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.invalidParam(let name, _) = error else {
                XCTFail("expected invalidParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "fontSize")
        }
    }

    func test_parse_themeV2PaletteModes_returnTheme() throws {
        // Bug #206: Feature #60's 5-theme palette (paper/sepia/dark/oled/
        // photo) must all be drivable from the debug URL. The pre-fix
        // ThemeMode enum accepted only dark|light, so sepia/oled/photo
        // verify slices got `parse.invalidParam` and silently fell back
        // to UI gestures. (`dark` + `light` are covered above.)
        for raw in ["paper", "sepia", "oled", "photo"] {
            let url = URL(string: "vreader-debug://theme?mode=\(raw)")!
            let cmd = try DebugCommand.parse(url)
            guard case .theme(let mode, let fontSize) = cmd else {
                XCTFail("mode=\(raw): expected .theme, got \(cmd)")
                continue
            }
            XCTAssertEqual(mode.rawValue, raw, "mode=\(raw) should round-trip")
            XCTAssertNil(fontSize)
        }
    }

    // MARK: - settle

    func test_parse_settleWithToken_returnsSettle() throws {
        let url = URL(string: "vreader-debug://settle?token=abc-123")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .settle(token: "abc-123"))
    }

    func test_parse_settleMissingToken_throwsMissingParam() {
        let url = URL(string: "vreader-debug://settle")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.missingParam(let name) = error else {
                XCTFail("expected missingParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "token")
        }
    }

    // MARK: - snapshot

    func test_parse_snapshotWithDest_returnsSnapshot() throws {
        let url = URL(string: "vreader-debug://snapshot?dest=state.json")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .snapshot(dest: "state.json"))
    }

    func test_parse_snapshotMissingDest_throwsMissingParam() {
        let url = URL(string: "vreader-debug://snapshot")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.missingParam(let name) = error else {
                XCTFail("expected missingParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "dest")
        }
    }

    // MARK: - eval

    func test_parse_evalWithBridgeAndBase64JS_returnsEvalWithDecodedJS() throws {
        let js = "document.querySelectorAll('.foliate-highlight').length"
        let encoded = Data(js.utf8).base64EncodedString()
        let urlEncoded = encoded.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "vreader-debug://eval?bridge=foliate&js=\(urlEncoded)")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .eval(bridge: "foliate", js: js))
    }

    func test_parse_evalInvalidBase64_throwsInvalidParam() {
        let url = URL(string: "vreader-debug://eval?bridge=foliate&js=not-valid-base64!!!")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.invalidParam(let name, _) = error else {
                XCTFail("expected invalidParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "js")
        }
    }

    func test_parse_evalWithSlashInBridge_throwsInvalidParam() {
        let js = Data("foo".utf8).base64EncodedString()
        let url = URL(string: "vreader-debug://eval?bridge=foo/bar&js=\(js)")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.invalidParam(let name, _) = error else {
                XCTFail("expected invalidParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "bridge")
        }
    }

    func test_parse_evalWithDotDotBridge_throwsInvalidParam() {
        let js = Data("foo".utf8).base64EncodedString()
        let url = URL(string: "vreader-debug://eval?bridge=..&js=\(js)")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.invalidParam(let name, _) = error else {
                XCTFail("expected invalidParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "bridge")
        }
    }

    func test_parse_evalMissingBridge_throwsMissingParam() {
        let js = Data("foo".utf8).base64EncodedString()
        let url = URL(string: "vreader-debug://eval?js=\(js)")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.missingParam(let name) = error else {
                XCTFail("expected missingParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "bridge")
        }
    }

    // MARK: - scheme + host validation

    func test_parse_wrongScheme_throwsInvalidScheme() {
        let url = URL(string: "https://reset")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.invalidScheme = error else {
                XCTFail("expected invalidScheme, got \(error)")
                return
            }
        }
    }

    func test_parse_unknownHost_throwsUnknownCommand() {
        let url = URL(string: "vreader-debug://teleport")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.unknownCommand(let name) = error else {
                XCTFail("expected unknownCommand, got \(error)")
                return
            }
            XCTAssertEqual(name, "teleport")
        }
    }

    func test_parse_missingHost_throwsUnknownCommand() {
        let url = URL(string: "vreader-debug://")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.unknownCommand = error else {
                XCTFail("expected unknownCommand, got \(error)")
                return
            }
        }
    }

    // MARK: - path rejection (extra path segments)

    func test_parse_settleWithExtraPath_throwsUnknownCommand() {
        let url = URL(string: "vreader-debug://settle/extra/path?token=abc")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.unknownCommand = error else {
                XCTFail("expected unknownCommand for path-bearing URL, got \(error)")
                return
            }
        }
    }

    func test_parse_resetWithSlashOnly_returnsResetCommand() throws {
        // Already covered, but kept here to assert "/" is the upper bound of accepted paths
        let url = URL(string: "vreader-debug://reset/")!
        XCTAssertEqual(try DebugCommand.parse(url), .reset)
    }

    // MARK: - duplicate query params

    func test_parse_seedWithDuplicateFixtureParam_throwsInvalidParam() {
        let url = URL(string: "vreader-debug://seed?fixture=alice&fixture=bad")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.invalidParam(let name, _) = error else {
                XCTFail("expected invalidParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "fixture")
        }
    }

    // MARK: - basename validation for token/dest

    func test_parse_settleWithSlashInToken_throwsInvalidParam() {
        let url = URL(string: "vreader-debug://settle?token=foo/bar")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.invalidParam(let name, _) = error else {
                XCTFail("expected invalidParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "token")
        }
    }

    func test_parse_settleWithDotDotToken_throwsInvalidParam() {
        // Path traversal: ".." passes the character-class check but is rejected
        // explicitly to stop `base.appendingPathComponent("..")` foot-guns in
        // future handlers.
        let url = URL(string: "vreader-debug://settle?token=..")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.invalidParam(let name, _) = error else {
                XCTFail("expected invalidParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "token")
        }
    }

    func test_parse_settleWithSingleDotToken_throwsInvalidParam() {
        let url = URL(string: "vreader-debug://settle?token=.")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.invalidParam = error else {
                XCTFail("expected invalidParam for `.`, got \(error)")
                return
            }
        }
    }

    func test_parse_snapshotWithTripleDotDest_throwsInvalidParam() {
        let url = URL(string: "vreader-debug://snapshot?dest=...")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.invalidParam(let name, _) = error else {
                XCTFail("expected invalidParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "dest")
        }
    }

    func test_parse_snapshotWithSpaceInDest_throwsInvalidParam() {
        let url = URL(string: "vreader-debug://snapshot?dest=hello%20world.json")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.invalidParam(let name, _) = error else {
                XCTFail("expected invalidParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "dest")
        }
    }

    func test_parse_snapshotWithLongDest_throwsInvalidParam() {
        let dest = String(repeating: "a", count: DebugCommand.basenameMaxLength + 1)
        let url = URL(string: "vreader-debug://snapshot?dest=\(dest)")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.invalidParam(let name, _) = error else {
                XCTFail("expected invalidParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "dest")
        }
    }

    func test_parse_snapshotWithValidDestUnderscoreDotHyphen_returnsSnapshot() throws {
        let url = URL(string: "vreader-debug://snapshot?dest=state-1_v2.json")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .snapshot(dest: "state-1_v2.json"))
    }

    // MARK: - tts (WI-4c-b — Feature #45 verification harness)

    func test_parse_ttsStartAction_returnsTtsStart() throws {
        let url = URL(string: "vreader-debug://tts?action=start")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .tts(action: "start"))
    }

    func test_parse_ttsStopAction_returnsTtsStop() throws {
        let url = URL(string: "vreader-debug://tts?action=stop")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .tts(action: "stop"))
    }

    func test_parse_ttsMissingAction_throwsMissingParam() {
        let url = URL(string: "vreader-debug://tts")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.missingParam(let name) = error else {
                XCTFail("expected missingParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "action")
        }
    }

    func test_parse_ttsInvalidAction_throwsInvalidParam() {
        let url = URL(string: "vreader-debug://tts?action=garbage")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.invalidParam(let name, _) = error else {
                XCTFail("expected invalidParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "action")
        }
    }

    // MARK: - search (Bug #238 — verification harness search-driver)

    func test_parse_searchWithQueryOnly_returnsSearchWithNilIndex() throws {
        let url = URL(string: "vreader-debug://search?query=alice")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .search(query: "alice", index: nil))
    }

    func test_parse_searchWithQueryAndIndex_returnsSearchWithIndex() throws {
        let url = URL(string: "vreader-debug://search?query=alice&index=2")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .search(query: "alice", index: 2))
    }

    func test_parse_searchWithIndexZero_returnsSearchWithIndexZero() throws {
        // Index 0 is valid — taps the first result.
        let url = URL(string: "vreader-debug://search?query=alice&index=0")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .search(query: "alice", index: 0))
    }

    func test_parse_searchWithPercentEncodedQuery_decodesIt() throws {
        // The percent-encoded query reaches the parser as URLComponents already
        // decodes %20 → space, %2B → '+', etc. Verifies the harness can pass a
        // multi-word query through the URL safely.
        let url = URL(string: "vreader-debug://search?query=white%20rabbit&index=1")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .search(query: "white rabbit", index: 1))
    }

    func test_parse_searchWithCJKQuery_decodesIt() throws {
        // CJK characters in the query are percent-encoded by the caller and
        // decoded by URLComponents. Mirrors the verify-cron's real workload
        // (Bug #182 cross-chapter EPUB search uses CJK text).
        let cjk = "白兔"
        let encoded = cjk.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!
        let url = URL(string: "vreader-debug://search?query=\(encoded)")!
        let cmd = try DebugCommand.parse(url)
        XCTAssertEqual(cmd, .search(query: cjk, index: nil))
    }

    func test_parse_searchMissingQuery_throwsMissingParam() {
        let url = URL(string: "vreader-debug://search")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.missingParam(let name) = error else {
                XCTFail("expected missingParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "query")
        }
    }

    func test_parse_searchEmptyQuery_throwsMissingParam() {
        let url = URL(string: "vreader-debug://search?query=")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.missingParam(let name) = error else {
                XCTFail("expected missingParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "query")
        }
    }

    func test_parse_searchIndexOnly_throwsMissingParam() {
        // index without query is an error — they go together. The harness
        // cannot meaningfully tap a result without first running a query.
        let url = URL(string: "vreader-debug://search?index=0")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.missingParam(let name) = error else {
                XCTFail("expected missingParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "query")
        }
    }

    func test_parse_searchNonIntegerIndex_throwsInvalidParam() {
        let url = URL(string: "vreader-debug://search?query=alice&index=notanint")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.invalidParam(let name, _) = error else {
                XCTFail("expected invalidParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "index")
        }
    }

    func test_parse_searchNegativeIndex_throwsInvalidParam() {
        let url = URL(string: "vreader-debug://search?query=alice&index=-1")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.invalidParam(let name, _) = error else {
                XCTFail("expected invalidParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "index")
        }
    }

    func test_parse_searchEmptyIndexValue_throwsInvalidParam() {
        // `index=` (empty value) is malformed — should not parse as 0 silently.
        let url = URL(string: "vreader-debug://search?query=alice&index=")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.invalidParam(let name, _) = error else {
                XCTFail("expected invalidParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "index")
        }
    }

    func test_parse_searchDuplicateQuery_throwsInvalidParam() {
        // Duplicate keys are rejected by the parser's queryParams helper.
        let url = URL(string: "vreader-debug://search?query=alice&query=bob")!
        XCTAssertThrowsError(try DebugCommand.parse(url)) { error in
            guard case DebugCommandError.invalidParam(let name, _) = error else {
                XCTFail("expected invalidParam, got \(error)")
                return
            }
            XCTAssertEqual(name, "query")
        }
    }
}

#endif
