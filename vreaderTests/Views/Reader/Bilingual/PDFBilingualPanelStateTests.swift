// Purpose: Feature #56 WI-13 — pin the pure derivation
// `PDFBilingualPanelState.panelState(...)`. The panel's state is a
// synchronous function of (viewModel, currentPage, pagesPerUnit,
// totalPages); the panel reads `vm.translationsByUnit` /
// `vm.unavailableUnits` / `vm.inFlightUnits` indexed by the panel's
// own synchronous unit derivation — NOT `vm.lastTriggerUnit`
// (Gate-2 v5 round-1 H1).
//
// @coordinates-with: PDFBilingualPanelState.swift,
//   PDFBilingualPanel.swift, BilingualReadingViewModel.swift,
//   PDFChapterTextProvider.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-13)

import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("Feature #56 WI-13 — PDFBilingualPanelState derivation")
struct PDFBilingualPanelStateTests {

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFBilingualState-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static let bookKey =
        "pdf:cc00112233445566778899aabbccddeeff00112233445566778899aabbccdd:4096"

    /// Build a disabled VM in a fresh dir.
    private func makeVM(dir: URL) -> BilingualReadingViewModel {
        BilingualReadingViewModel(
            bookFingerprintKey: Self.bookKey, perBookBaseURL: dir)
    }

    /// Build an enabled VM, with the setup-sheet dismissed (so it looks
    /// like a "already configured for this book" state).
    private func makeEnabledVM(dir: URL) -> BilingualReadingViewModel {
        let vm = makeVM(dir: dir)
        vm.setEnabled(true)
        vm.dismissSetupSheet()
        return vm
    }

    /// Synchronous mirror of `PDFChapterTextProvider`'s unit-id encoding.
    /// Kept here so the tests pin the contract that the panel's own
    /// derivation must match.
    private static func encodedUnit(currentPage: Int, pagesPerUnit: Int, totalPages: Int) -> TranslationUnitID {
        let perUnit = max(1, pagesPerUnit)
        let start = (currentPage / perUnit) * perUnit
        let end = min(start + perUnit - 1, totalPages - 1)
        return TranslationUnitID(kind: .pdfPageRange, value: "\(start)-\(end)")
    }

    // MARK: - .off branches

    @Test func nilViewModel_returnsOff() throws {
        let state = PDFBilingualPanelState.panelState(
            viewModel: nil, currentPage: 0, pagesPerUnit: 1, totalPages: 10)
        #expect(state == .off)
    }

    @Test func viewModelDisabled_returnsOff() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = makeVM(dir: dir)
        // Default: isEnabled == false.
        let state = PDFBilingualPanelState.panelState(
            viewModel: vm, currentPage: 0, pagesPerUnit: 1, totalPages: 10)
        #expect(state == .off)
    }

    // MARK: - .empty branches

    @Test func zeroTotalPages_returnsEmpty() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = makeEnabledVM(dir: dir)
        let state = PDFBilingualPanelState.panelState(
            viewModel: vm, currentPage: 0, pagesPerUnit: 1, totalPages: 0)
        #expect(state == .empty)
    }

    @Test func negativeTotalPages_returnsEmpty() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = makeEnabledVM(dir: dir)
        let state = PDFBilingualPanelState.panelState(
            viewModel: vm, currentPage: 0, pagesPerUnit: 1, totalPages: -1)
        #expect(state == .empty)
    }

    @Test func cachedEmptySegments_returnsEmpty() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = makeEnabledVM(dir: dir)
        let unit = Self.encodedUnit(currentPage: 0, pagesPerUnit: 1, totalPages: 10)
        // The translation service returned [] for an image-only page —
        // the panel paints empty, not "translated([])".
        vm.translationsByUnit[unit] = []
        let state = PDFBilingualPanelState.panelState(
            viewModel: vm, currentPage: 0, pagesPerUnit: 1, totalPages: 10)
        #expect(state == .empty)
    }

    // MARK: - .translated branch

    @Test func cachedTranslation_returnsTranslated() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = makeEnabledVM(dir: dir)
        let unit = Self.encodedUnit(currentPage: 0, pagesPerUnit: 1, totalPages: 10)
        let segments = ["第一段", "第二段"]
        vm.translationsByUnit[unit] = segments
        let state = PDFBilingualPanelState.panelState(
            viewModel: vm, currentPage: 0, pagesPerUnit: 1, totalPages: 10)
        #expect(state == .translated(segments: segments))
    }

    // MARK: - .offline branch

    @Test func unitMarkedUnavailable_returnsOffline() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = makeEnabledVM(dir: dir)
        let unit = Self.encodedUnit(currentPage: 5, pagesPerUnit: 1, totalPages: 10)
        vm.unavailableUnits.insert(unit)
        let state = PDFBilingualPanelState.panelState(
            viewModel: vm, currentPage: 5, pagesPerUnit: 1, totalPages: 10)
        #expect(state == .offline)
    }

    // MARK: - .loading branches

    @Test func unitInFlight_returnsLoading() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = makeEnabledVM(dir: dir)
        let unit = Self.encodedUnit(currentPage: 3, pagesPerUnit: 1, totalPages: 10)
        vm.inFlightUnits.insert(unit)
        vm.isFetching = true
        let state = PDFBilingualPanelState.panelState(
            viewModel: vm, currentPage: 3, pagesPerUnit: 1, totalPages: 10)
        #expect(state == .loading)
    }

    @Test func noCacheNoFlight_returnsLoading() throws {
        // Initial-paint window: VM has nothing for this unit yet (the
        // prefetch hasn't started). The panel renders as loading
        // because a fetch is imminent — never .empty in this window.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = makeEnabledVM(dir: dir)
        let state = PDFBilingualPanelState.panelState(
            viewModel: vm, currentPage: 0, pagesPerUnit: 1, totalPages: 10)
        #expect(state == .loading)
    }

    // MARK: - Unit-arithmetic boundaries

    @Test func singlePageBook_unitIs00() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = makeEnabledVM(dir: dir)
        let unit = Self.encodedUnit(currentPage: 0, pagesPerUnit: 1, totalPages: 1)
        #expect(unit.value == "0-0")
        vm.translationsByUnit[unit] = ["译文"]
        let state = PDFBilingualPanelState.panelState(
            viewModel: vm, currentPage: 0, pagesPerUnit: 1, totalPages: 1)
        #expect(state == .translated(segments: ["译文"]))
    }

    @Test func lastPageInBook_unitIsLast() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = makeEnabledVM(dir: dir)
        let unit = Self.encodedUnit(currentPage: 9, pagesPerUnit: 1, totalPages: 10)
        #expect(unit.value == "9-9")
        vm.translationsByUnit[unit] = ["last"]
        let state = PDFBilingualPanelState.panelState(
            viewModel: vm, currentPage: 9, pagesPerUnit: 1, totalPages: 10)
        #expect(state == .translated(segments: ["last"]))
    }

    @Test func pagesPerUnitGreaterThanOne_groupsRanges() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = makeEnabledVM(dir: dir)
        // pagesPerUnit = 3, totalPages = 10 → groups [0-2],[3-5],[6-8],[9-9].
        // Page 4 is in unit "3-5".
        let unit = Self.encodedUnit(currentPage: 4, pagesPerUnit: 3, totalPages: 10)
        #expect(unit.value == "3-5")
        vm.translationsByUnit[unit] = ["grouped"]
        let state = PDFBilingualPanelState.panelState(
            viewModel: vm, currentPage: 4, pagesPerUnit: 3, totalPages: 10)
        #expect(state == .translated(segments: ["grouped"]))
    }

    @Test func pagesPerUnitTailUnit_clampsToTotalMinusOne() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = makeEnabledVM(dir: dir)
        // pagesPerUnit = 4, totalPages = 10 → trailing unit "8-9" (clamped).
        let unit = Self.encodedUnit(currentPage: 9, pagesPerUnit: 4, totalPages: 10)
        #expect(unit.value == "8-9")
        vm.translationsByUnit[unit] = ["tail"]
        let state = PDFBilingualPanelState.panelState(
            viewModel: vm, currentPage: 9, pagesPerUnit: 4, totalPages: 10)
        #expect(state == .translated(segments: ["tail"]))
    }

    @Test func currentPageOutOfRange_returnsLoading() throws {
        // A page index beyond totalPages is a transient state the
        // host should never invoke us in, but the derivation must not
        // crash. Clamping to the last unit and then reading is wrong
        // (it could flash the last page's translation); the safest
        // behavior is "loading" (no translation cached for an
        // out-of-range unit), which the panel paints harmlessly.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = makeEnabledVM(dir: dir)
        let state = PDFBilingualPanelState.panelState(
            viewModel: vm, currentPage: 99, pagesPerUnit: 1, totalPages: 10)
        // The derived unit string is "99-9" with end clamped to 9 —
        // a unit that no real prefetch would target, so cache always
        // misses → loading.
        #expect(state == .loading)
    }

    // MARK: - .off precedence

    @Test func offEnabledFalse_precedesEmpty() throws {
        // Disabled VM with totalPages = 0 — the .off precedence beats
        // .empty so a fresh book doesn't blink "no text on page" before
        // bilingual is enabled.
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let vm = makeVM(dir: dir) // disabled
        let state = PDFBilingualPanelState.panelState(
            viewModel: vm, currentPage: 0, pagesPerUnit: 1, totalPages: 0)
        #expect(state == .off)
    }

    // MARK: - pageLabel helper (small ergonomic API)

    @Test func pageLabel_singlePagePerUnit_isOneIndexed() throws {
        let label = PDFBilingualPanelState.pageLabel(
            currentPage: 0, pagesPerUnit: 1, totalPages: 10)
        #expect(label == "Page 1")
    }

    @Test func pageLabel_multiPagePerUnit_isRange() throws {
        let label = PDFBilingualPanelState.pageLabel(
            currentPage: 4, pagesPerUnit: 3, totalPages: 10)
        // Unit "3-5" → "Pages 4-6" one-indexed.
        #expect(label == "Pages 4-6")
    }

    @Test func pageLabel_multiPagePerUnit_lastUnitClampedToTotal() throws {
        let label = PDFBilingualPanelState.pageLabel(
            currentPage: 9, pagesPerUnit: 4, totalPages: 10)
        // Unit "8-9" → "Pages 9-10" one-indexed.
        #expect(label == "Pages 9-10")
    }

    @Test func pageLabel_emptyBook_isFallback() throws {
        let label = PDFBilingualPanelState.pageLabel(
            currentPage: 0, pagesPerUnit: 1, totalPages: 0)
        // Don't synthesize a fake "Page 1" of an empty book.
        #expect(label == "—")
    }
}
