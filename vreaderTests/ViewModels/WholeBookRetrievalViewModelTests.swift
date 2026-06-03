// Feature #86 WI-5b: the WholeBookRetrievalViewModel phase machine — arm /
// read→ready / cancel→partial, progress, and the available-context gate. Uses the
// real WholeBookReducer with a fake condense closure (no AIService).

import Testing
import Foundation
@testable import vreader

@Suite("WholeBookRetrievalViewModel (Feature #86 WI-5b)")
@MainActor
struct WholeBookRetrievalViewModelTests {

    @Test func arm_fromIdle_movesToArmed() {
        let vm = WholeBookRetrievalViewModel()
        #expect(vm.phase == .idle)
        vm.arm()
        #expect(vm.phase == .armed)
    }

    @Test func disarm_returnsToIdle() {
        let vm = WholeBookRetrievalViewModel()
        vm.arm()
        vm.disarm()
        #expect(vm.phase == .idle)
    }

    @Test func read_completes_movesToReady_withContext() async {
        let vm = WholeBookRetrievalViewModel()
        vm.read(
            fullText: String(repeating: "x", count: 300), chunkBudgetUTF16: 100,
            digestBudgetUTF16: 10_000, maxChunks: 50
        ) { chunk in "[sum:\(chunk.utf16.count)]" }
        await vm.readTask?.value
        guard case let .ready(coverage) = vm.phase else {
            Issue.record("expected .ready, got \(vm.phase)"); return
        }
        #expect(coverage.isComplete)
        #expect(vm.isReady)
        #expect(vm.availableContext?.isEmpty == false)
        #expect(vm.progressFraction == 1.0)
    }

    @Test func read_overflow_movesToPartial_notReady() async {
        let vm = WholeBookRetrievalViewModel()
        vm.read(
            fullText: String(repeating: "z", count: 1000), chunkBudgetUTF16: 100,
            digestBudgetUTF16: 10_000, maxChunks: 3   // only 3 of 10 chunks → partial
        ) { _ in "s" }
        await vm.readTask?.value
        guard case let .partial(coverage) = vm.phase else {
            Issue.record("expected .partial, got \(vm.phase)"); return
        }
        #expect(!coverage.isComplete)
        #expect(!vm.isReady)
        #expect(vm.availableContext != nil)   // a partial digest is still usable text
    }

    @Test func cancel_midRead_movesToPartial() async {
        let reducer = WholeBookReducer()
        let vm = WholeBookRetrievalViewModel(reducerFactory: { reducer })
        nonisolated(unsafe) var calls = 0
        vm.read(
            fullText: String(repeating: "w", count: 1000), chunkBudgetUTF16: 100,
            digestBudgetUTF16: 10_000, maxChunks: 50
        ) { _ in
            calls += 1
            if calls == 2 { await reducer.cancel() }   // cancel after the 2nd chunk
            return "s"
        }
        await vm.readTask?.value
        guard case let .partial(coverage) = vm.phase else {
            Issue.record("expected .partial after cancel, got \(vm.phase)"); return
        }
        #expect(!coverage.isComplete)
        #expect(coverage.coveredSpans.count <= 3)
    }

    /// Gate-4: disarm during an in-flight read bumps the epoch + cancels the
    /// reducer, so the stale read's terminal write is discarded — the phase stays
    /// `.idle`, never resurrecting `.ready`/`.partial` after the user left whole-book.
    @Test func disarm_duringRead_staysIdle_noStaleWrite() async {
        let reducer = WholeBookReducer()
        let vm = WholeBookRetrievalViewModel(reducerFactory: { reducer })
        nonisolated(unsafe) var calls = 0
        vm.read(
            fullText: String(repeating: "y", count: 1000), chunkBudgetUTF16: 100,
            digestBudgetUTF16: 10_000, maxChunks: 50
        ) { _ in
            calls += 1
            if calls == 1 { await MainActor.run { vm.disarm() } }   // leave whole-book mid-read
            return "s"
        }
        await vm.readTask?.value
        #expect(vm.phase == .idle)   // the late read never wrote ready/partial
    }

    @Test func arm_fromPartial_reArms() async {
        let vm = WholeBookRetrievalViewModel()
        vm.read(
            fullText: String(repeating: "z", count: 1000), chunkBudgetUTF16: 100,
            digestBudgetUTF16: 10_000, maxChunks: 3
        ) { _ in "s" }
        await vm.readTask?.value
        #expect({ if case .partial = vm.phase { return true } else { return false } }())
        vm.arm()
        #expect(vm.phase == .armed)
    }
}
