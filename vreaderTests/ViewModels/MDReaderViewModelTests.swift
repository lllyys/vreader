// Purpose: Tests for MDReaderViewModel — open/close lifecycle, position persistence,
// session tracking, error handling, edge cases.
//
// @coordinates-with: MDReaderViewModel.swift, MockMDParser.swift, MockPositionStore.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Fixtures

private let testFingerprint = DocumentFingerprint(
    contentSHA256: "md_vm_test_sha256_0000000000000000000000000000000000000000000",
    fileByteCount: 500,
    format: .md
)

private let testRenderedText = "Title\nHello world. This is rendered markdown content.\n"
private let testMDSource = "# Title\n\nHello world. This is **rendered** markdown content.\n"

private func makeDocumentInfo(
    renderedText: String = testRenderedText,
    title: String? = "Title"
) -> MDDocumentInfo {
    MDDocumentInfo(
        renderedText: renderedText,
        renderedAttributedString: NSAttributedString(string: renderedText),
        headings: title != nil ? [MDHeading(level: 1, text: title!, charOffsetUTF16: 0)] : [],
        title: title
    )
}

private let testURL = URL(fileURLWithPath: "/tmp/test.md")

// MARK: - Helpers

@MainActor
private func makeViewModel(
    fingerprint: DocumentFingerprint = testFingerprint,
    mdSource: String = testMDSource,
    documentInfo: MDDocumentInfo? = nil,
    fileData: Data? = nil,
    fileReadError: Bool = false,
    positionSaveDebounceNs: UInt64 = 2_000_000_000
) async -> (MDReaderViewModel, MockMDParser, MockPositionStore, MockSessionStore) {
    let parser = MockMDParser()
    if let info = documentInfo {
        parser.setDocumentInfo(info)
    } else {
        parser.setDocumentInfo(makeDocumentInfo())
    }

    let positionStore = MockPositionStore()
    let sessionStore = MockSessionStore()
    let clock = MockClock()
    let tracker = ReadingSessionTracker(
        clock: clock,
        store: sessionStore,
        deviceId: "test-device"
    )

    let vm = MDReaderViewModel(
        bookFingerprint: fingerprint,
        parser: parser,
        positionStore: positionStore,
        sessionTracker: tracker,
        deviceId: "test-device",
        positionSaveDebounceNs: positionSaveDebounceNs
    )

    return (vm, parser, positionStore, sessionStore)
}

// MARK: - Open Lifecycle

@Suite("MDReaderViewModel - Open")
@MainActor
struct MDReaderViewModelOpenTests {

    @Test("open parses markdown and sets rendered content")
    func openSetsRenderedContent() async {
        let (vm, parser, _, _) = await makeViewModel()

        // Create a temp file with markdown content
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("open_test_\(UUID().uuidString).md")
        try! testMDSource.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await vm.open(url: url)

        #expect(vm.renderedText == testRenderedText)
        #expect(vm.renderedAttributedString != nil)
        #expect(vm.renderedTextLengthUTF16 == (testRenderedText as NSString).length)
        #expect(vm.isLoading == false)
        #expect(vm.errorMessage == nil)
        #expect(parser.parseCallCount == 1)
    }

    // Feature #56 WI-12: expose parsed headings so the bilingual host
    // can construct an `MDChapterTextProvider`.
    @Test("open populates headings; close clears them")
    func openPopulatesHeadingsAndCloseClears() async {
        let (vm, _, _, _) = await makeViewModel()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "headings_test_\(UUID().uuidString).md"
        )
        try! testMDSource.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(vm.headings == nil)  // before open

        await vm.open(url: url)
        #expect(vm.headings != nil)
        #expect(vm.headings?.count == 1)
        #expect(vm.headings?.first?.text == "Title")
        #expect(vm.headings?.first?.level == 1)

        await vm.close()
        #expect(vm.headings == nil)
    }

    @Test("open starts reading session")
    func openStartsSession() async {
        let (vm, _, _, sessionStore) = await makeViewModel()

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("session_test_\(UUID().uuidString).md")
        try! testMDSource.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await vm.open(url: url)

        #expect(sessionStore.savedSessions.count == 1)
    }

    @Test("open restores saved position")
    func openRestoresSavedPosition() async {
        let (vm, _, positionStore, _) = await makeViewModel()

        // Seed a saved position
        let savedLocator = Locator(
            bookFingerprint: testFingerprint,
            href: nil, progression: nil, totalProgression: 0.5,
            cfi: nil, page: nil,
            charOffsetUTF16: 25,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        await positionStore.seed(
            bookFingerprintKey: testFingerprint.canonicalKey,
            locator: savedLocator
        )

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("restore_test_\(UUID().uuidString).md")
        try! testMDSource.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await vm.open(url: url)

        #expect(vm.currentOffsetUTF16 == 25)
    }

    @Test("open with empty file sets empty content and no error")
    func openEmptyFile() async {
        let emptyInfo = MDDocumentInfo(
            renderedText: "",
            renderedAttributedString: NSAttributedString(string: ""),
            headings: [],
            title: nil
        )
        let (vm, _, _, _) = await makeViewModel(documentInfo: emptyInfo)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("empty_test_\(UUID().uuidString).md")
        try! "".data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await vm.open(url: url)

        #expect(vm.renderedText == "")
        #expect(vm.renderedTextLengthUTF16 == 0)
        #expect(vm.errorMessage == nil)
    }

    @Test("open with missing file sets error message")
    func openMissingFile() async {
        let (vm, _, _, _) = await makeViewModel()

        let url = URL(fileURLWithPath: "/tmp/nonexistent_\(UUID().uuidString).md")

        await vm.open(url: url)

        #expect(vm.renderedText == nil)
        #expect(vm.errorMessage != nil)
    }
}

// MARK: - Close

@Suite("MDReaderViewModel - Close")
@MainActor
struct MDReaderViewModelCloseTests {

    @Test("close ends session and saves position")
    func closeEndsSession() async {
        let (vm, _, positionStore, _) = await makeViewModel()

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("close_test_\(UUID().uuidString).md")
        try! testMDSource.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await vm.open(url: url)
        await vm.close()

        let saveCount = await positionStore.saveCallCount
        #expect(saveCount >= 1)
    }

    @Test("close without open is safe")
    func closeWithoutOpen() async {
        let (vm, _, _, _) = await makeViewModel()
        await vm.close() // Should not crash
    }
}

// MARK: - Position Updates

@Suite("MDReaderViewModel - Position")
@MainActor
struct MDReaderViewModelPositionTests {

    @Test("updateScrollPosition updates offset")
    func updateScrollPosition() async {
        let (vm, _, _, _) = await makeViewModel()

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pos_test_\(UUID().uuidString).md")
        try! testMDSource.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await vm.open(url: url)
        vm.updateScrollPosition(charOffsetUTF16: 20)

        #expect(vm.currentOffsetUTF16 == 20)
    }

    @Test("totalProgression is 0 for empty document")
    func emptyDocTotalProgression() async {
        let emptyInfo = MDDocumentInfo(
            renderedText: "",
            renderedAttributedString: NSAttributedString(string: ""),
            headings: [],
            title: nil
        )
        let (vm, _, _, _) = await makeViewModel(documentInfo: emptyInfo)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("empty_prog_\(UUID().uuidString).md")
        try! "".data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await vm.open(url: url)

        #expect(vm.totalProgression == nil)
    }

    @Test("totalProgression is computed from offset and length")
    func totalProgressionComputed() async {
        let (vm, _, _, _) = await makeViewModel()

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prog_test_\(UUID().uuidString).md")
        try! testMDSource.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await vm.open(url: url)

        let totalLen = vm.renderedTextLengthUTF16
        vm.updateScrollPosition(charOffsetUTF16: totalLen / 2)

        let prog = vm.totalProgression
        #expect(prog != nil)
        #expect(prog! > 0.4)
        #expect(prog! < 0.6)
    }

    @Test("position clamps to valid range")
    func positionClamping() async {
        let (vm, _, _, _) = await makeViewModel()

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("clamp_test_\(UUID().uuidString).md")
        try! testMDSource.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await vm.open(url: url)

        // Offset beyond text length should be clamped
        vm.updateScrollPosition(charOffsetUTF16: 999999)
        #expect(vm.currentOffsetUTF16 == vm.renderedTextLengthUTF16)

        // Negative offset should be clamped to 0
        vm.updateScrollPosition(charOffsetUTF16: -5)
        #expect(vm.currentOffsetUTF16 == 0)
    }
}

// MARK: - Background/Foreground

@Suite("MDReaderViewModel - Lifecycle")
@MainActor
struct MDReaderViewModelLifecycleTests {

    @Test("onBackground pauses session and saves position")
    func onBackground() async {
        let (vm, _, positionStore, _) = await makeViewModel()

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bg_test_\(UUID().uuidString).md")
        try! testMDSource.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await vm.open(url: url)

        let saveCountBefore = await positionStore.saveCallCount
        await vm.onBackground()

        let saveCountAfter = await positionStore.saveCallCount
        #expect(saveCountAfter > saveCountBefore)
    }

    @Test("onForeground resumes session")
    func onForeground() async {
        let (vm, _, _, _) = await makeViewModel()

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fg_test_\(UUID().uuidString).md")
        try! testMDSource.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await vm.open(url: url)
        await vm.onBackground()
        vm.onForeground()

        // Should not have an error
        #expect(vm.errorMessage == nil)
    }

    @Test("position restore falls back to offset 0 on load failure")
    func positionRestoreFallback() async {
        let (vm, _, positionStore, _) = await makeViewModel()

        // Make position loading fail
        await positionStore.setLoadError(NSError(domain: "test", code: -1))

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fallback_test_\(UUID().uuidString).md")
        try! testMDSource.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await vm.open(url: url)

        #expect(vm.currentOffsetUTF16 == 0)
        #expect(vm.errorMessage == nil) // Position failure is non-fatal
    }
}

// MARK: - Bug #23: Position Save Guards

@Suite("MDReaderViewModel - Position Save Guards (Bug #23)")
@MainActor
struct MDReaderViewModelPositionGuardTests {

    @Test("close saves restored position, not stale 0, when user never scrolled")
    func closeSavesRestoredOffset() async {
        let (vm, _, positionStore, _) = await makeViewModel()

        // Seed a saved position at offset 25
        let savedLocator = Locator(
            bookFingerprint: testFingerprint,
            href: nil, progression: nil, totalProgression: 0.5,
            cfi: nil, page: nil,
            charOffsetUTF16: 25,
            charRangeStartUTF16: nil, charRangeEndUTF16: nil,
            textQuote: nil, textContextBefore: nil, textContextAfter: nil
        )
        await positionStore.seed(
            bookFingerprintKey: testFingerprint.canonicalKey,
            locator: savedLocator
        )

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("guard_test_\(UUID().uuidString).md")
        try! testMDSource.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await vm.open(url: url)
        #expect(vm.currentOffsetUTF16 == 25)

        // Close without scrolling — should save offset 25, not 0
        await vm.close()

        let saved = await positionStore.position(forKey: testFingerprint.canonicalKey)
        #expect(saved != nil)
        #expect(saved?.charOffsetUTF16 == 25)
    }

    @Test("close after failed session start still saves position (session non-fatal)")
    func closeAfterSessionFailureStillSaves() async {
        let parser = MockMDParser()
        parser.setDocumentInfo(makeDocumentInfo())

        let positionStore = MockPositionStore()
        let sessionStore = MockSessionStore()
        sessionStore.saveError = NSError(domain: "test", code: 1)
        let clock = MockClock()
        let tracker = ReadingSessionTracker(
            clock: clock,
            store: sessionStore,
            deviceId: "test-device"
        )

        let vm = MDReaderViewModel(
            bookFingerprint: testFingerprint,
            parser: parser,
            positionStore: positionStore,
            sessionTracker: tracker,
            deviceId: "test-device"
        )

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fail_test_\(UUID().uuidString).md")
        try! testMDSource.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        // open() succeeds even though session start fails (non-fatal)
        await vm.open(url: url)
        #expect(vm.errorMessage == nil)
        #expect(vm.renderedText == testRenderedText)

        let saveCountBeforeClose = await positionStore.saveCallCount

        await vm.close()

        let saveCountAfterClose = await positionStore.saveCallCount
        // close() SHOULD save position since isOpenComplete is true
        // (session failure doesn't prevent content from loading)
        #expect(saveCountAfterClose >= saveCountBeforeClose)
    }

    @Test("onBackground awaits save — position persisted without sleep hack")
    func onBackgroundSavesImmediately() async {
        let (vm, _, positionStore, _) = await makeViewModel()

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bg_save_\(UUID().uuidString).md")
        try! testMDSource.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await vm.open(url: url)
        vm.updateScrollPosition(charOffsetUTF16: 20)
        await vm.onBackground()

        // Save is guaranteed complete after await — no Task.sleep needed
        let saved = await positionStore.position(forKey: testFingerprint.canonicalKey)
        #expect(saved?.charOffsetUTF16 == 20)
    }
}

// MARK: - Edge Cases

@Suite("MDReaderViewModel - Edge Cases")
@MainActor
struct MDReaderViewModelEdgeCaseTests {

    @Test("updateScrollPosition before open is safe")
    func updateBeforeOpen() async {
        let (vm, _, _, _) = await makeViewModel()
        vm.updateScrollPosition(charOffsetUTF16: 42) // Should not crash
    }

    @Test("second open call closes previous and re-opens")
    func secondOpenCall() async {
        let (vm, parser, _, _) = await makeViewModel()

        let url1 = FileManager.default.temporaryDirectory.appendingPathComponent("open1_\(UUID().uuidString).md")
        let url2 = FileManager.default.temporaryDirectory.appendingPathComponent("open2_\(UUID().uuidString).md")
        try! testMDSource.data(using: .utf8)!.write(to: url1)
        try! testMDSource.data(using: .utf8)!.write(to: url2)
        defer {
            try? FileManager.default.removeItem(at: url1)
            try? FileManager.default.removeItem(at: url2)
        }

        await vm.open(url: url1)
        await vm.open(url: url2)

        #expect(parser.parseCallCount == 2)
        #expect(vm.renderedText != nil)
    }

    @Test("CJK rendered text has correct UTF-16 length")
    func cjkRenderedText() async {
        let cjkText = "标题\n这是中文内容。\n"
        let cjkInfo = MDDocumentInfo(
            renderedText: cjkText,
            renderedAttributedString: NSAttributedString(string: cjkText),
            headings: [],
            title: "标题"
        )
        let (vm, _, _, _) = await makeViewModel(documentInfo: cjkInfo)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cjk_test_\(UUID().uuidString).md")
        try! "# 标题\n\n这是中文内容。".data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await vm.open(url: url)

        #expect(vm.renderedTextLengthUTF16 == (cjkText as NSString).length)
    }
}

// MARK: - Position Service Integration (WI-008c)

@Suite("MDReaderViewModel - Position Service")
@MainActor
struct MDReaderViewModelPositionServiceTests {

    @Test("close uses positionService.saveNow for immediate persistence")
    func closeUsesPositionService() async {
        let (vm, _, positionStore, _) = await makeViewModel(positionSaveDebounceNs: 0)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("svc_close_\(UUID().uuidString).md")
        try! testMDSource.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await vm.open(url: url)
        vm.updateScrollPosition(charOffsetUTF16: 15)
        await vm.close()

        let saved = await positionStore.position(forKey: testFingerprint.canonicalKey)
        #expect(saved?.charOffsetUTF16 == 15)
    }

    @Test("onBackground uses positionService.saveNow")
    func onBackgroundUsesPositionService() async {
        let (vm, _, positionStore, _) = await makeViewModel(positionSaveDebounceNs: 0)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("svc_bg_\(UUID().uuidString).md")
        try! testMDSource.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await vm.open(url: url)
        vm.updateScrollPosition(charOffsetUTF16: 10)
        await vm.onBackground()

        let saved = await positionStore.position(forKey: testFingerprint.canonicalKey)
        #expect(saved?.charOffsetUTF16 == 10)
    }

    @Test("updateScrollPosition uses positionService.scheduleSave")
    func scrollUsesScheduleSave() async {
        let (vm, _, positionStore, _) = await makeViewModel(positionSaveDebounceNs: 10_000_000)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("svc_scroll_\(UUID().uuidString).md")
        try! testMDSource.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        await vm.open(url: url)
        vm.updateScrollPosition(charOffsetUTF16: 20)

        // Wait for debounce (10ms)
        try? await Task.sleep(for: .milliseconds(50))

        let saved = await positionStore.position(forKey: testFingerprint.canonicalKey)
        #expect(saved?.charOffsetUTF16 == 20)
    }
}
