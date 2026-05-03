// Purpose: Tests for BookFileState enum — raw value round-trip, isReadable
// and canDownload truth tables, allCases stability. Foundational tests for
// feature #47 (selective restore + lazy downloads).

import Testing
import Foundation
@testable import vreader

@Suite("BookFileState")
struct BookFileStateTests {

    // MARK: - Raw value round-trip

    @Test func localRawIsLocal() {
        #expect(BookFileState.local.rawValue == "local")
    }

    @Test func remoteOnlyRawIsRemoteOnly() {
        #expect(BookFileState.remoteOnly.rawValue == "remoteOnly")
    }

    @Test func downloadingRawIsDownloading() {
        #expect(BookFileState.downloading.rawValue == "downloading")
    }

    @Test func failedRawIsFailed() {
        #expect(BookFileState.failed.rawValue == "failed")
    }

    @Test func missingRemoteRawIsMissingRemote() {
        #expect(BookFileState.missingRemote.rawValue == "missingRemote")
    }

    @Test(arguments: [
        BookFileState.local,
        BookFileState.remoteOnly,
        BookFileState.downloading,
        BookFileState.failed,
        BookFileState.missingRemote
    ])
    func rawValueRoundTrip(_ state: BookFileState) {
        let raw = state.rawValue
        let parsed = BookFileState(rawValue: raw)
        #expect(parsed == state)
    }

    @Test func unknownRawValueProducesNil() {
        #expect(BookFileState(rawValue: "garbage") == nil)
        #expect(BookFileState(rawValue: "") == nil)
    }

    // MARK: - allCases stability

    @Test func allCasesHasExactlyFiveStates() {
        #expect(BookFileState.allCases.count == 5)
    }

    @Test func allCasesContainsExpectedStates() {
        let cases = Set(BookFileState.allCases)
        #expect(cases == [.local, .remoteOnly, .downloading, .failed, .missingRemote])
    }

    // MARK: - isReadable truth table

    @Test func localIsReadable() {
        #expect(BookFileState.local.isReadable == true)
    }

    @Test(arguments: [
        BookFileState.remoteOnly,
        BookFileState.downloading,
        BookFileState.failed,
        BookFileState.missingRemote
    ])
    func nonLocalStatesAreNotReadable(_ state: BookFileState) {
        #expect(state.isReadable == false)
    }

    // MARK: - canDownload truth table

    @Test(arguments: [
        BookFileState.remoteOnly,
        BookFileState.failed
    ])
    func canDownloadTrueForRemoteOnlyAndFailed(_ state: BookFileState) {
        #expect(state.canDownload == true)
    }

    @Test(arguments: [
        BookFileState.local,
        BookFileState.downloading,
        BookFileState.missingRemote
    ])
    func canDownloadFalseForLocalDownloadingMissing(_ state: BookFileState) {
        #expect(state.canDownload == false)
    }

    // MARK: - Codable round-trip

    @Test func codableRoundTrip() throws {
        let original = BookFileState.remoteOnly
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BookFileState.self, from: data)
        #expect(decoded == original)
    }

    @Test func codableEncodesAsRawString() throws {
        let data = try JSONEncoder().encode(BookFileState.downloading)
        let s = String(data: data, encoding: .utf8)
        #expect(s == "\"downloading\"")
    }
}
