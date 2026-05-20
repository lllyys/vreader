// Purpose: Tests for the value types in BookTranslationProgress.swift —
// BookTranslationProgress + BookTranslationEstimate (feature #56 WI-14).
//
// @coordinates-with: BookTranslationProgress.swift,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-14)

import Testing
import Foundation
@testable import vreader

@Suite("BookTranslationProgress")
struct BookTranslationProgressTests {

    // MARK: - BookTranslationProgress

    @Test func idle_hasZeroProgressAndIsNotActive() {
        let progress = BookTranslationProgress.idle(total: 12)
        #expect(progress.completed == 0)
        #expect(progress.total == 12)
        #expect(progress.phase == .idle)
        #expect(progress.isRunning == false)
        #expect(progress.fraction == 0.0)
    }

    @Test func zeroTotal_idle_completesImmediatelyWithFractionZero() {
        // A book with no translation units — fraction is 0 not NaN.
        let progress = BookTranslationProgress.idle(total: 0)
        #expect(progress.fraction == 0.0)
        #expect(progress.isFinished == false)
    }

    @Test func running_isRunning_andFractionMatchesRatio() {
        let progress = BookTranslationProgress(
            phase: .running, completed: 5, total: 20)
        #expect(progress.isRunning == true)
        #expect(progress.isFinished == false)
        #expect(progress.fraction == 0.25)
    }

    @Test func completed_isFinished_andFractionIsOne() {
        let progress = BookTranslationProgress(
            phase: .completed, completed: 20, total: 20)
        #expect(progress.isFinished == true)
        #expect(progress.isRunning == false)
        #expect(progress.fraction == 1.0)
    }

    @Test func cancelled_isCancelled_andRetainsPartialProgress() {
        let progress = BookTranslationProgress(
            phase: .cancelled, completed: 7, total: 20)
        #expect(progress.isCancelled == true)
        #expect(progress.isFinished == false)
        #expect(progress.isRunning == false)
        #expect(progress.completed == 7)
    }

    @Test func zeroUnitBook_completedAtZeroOverZero_isFinishedAndNotErroring() {
        // Per plan: "a book with zero units completes immediately with a 0/0
        // progress and no error". Fraction is 0 (not NaN), isFinished is true.
        let progress = BookTranslationProgress(
            phase: .completed, completed: 0, total: 0)
        #expect(progress.isFinished == true)
        #expect(progress.fraction == 0.0)
    }

    @Test func failed_isNotRunning_andCarriesPartialCount() {
        let progress = BookTranslationProgress(
            phase: .failed, completed: 4, total: 12)
        #expect(progress.isRunning == false)
        #expect(progress.isFinished == false)
        #expect(progress.completed == 4)
    }

    @Test func equality_byPhaseAndCounts() {
        let a = BookTranslationProgress(phase: .running, completed: 3, total: 10)
        let b = BookTranslationProgress(phase: .running, completed: 3, total: 10)
        let c = BookTranslationProgress(phase: .running, completed: 4, total: 10)
        #expect(a == b)
        #expect(a != c)
    }

    // MARK: - BookTranslationEstimate

    @Test func estimate_unitCount_isReadable() {
        let estimate = BookTranslationEstimate(unitCount: 12)
        #expect(estimate.unitCount == 12)
        #expect(estimate.approximateInputTokens == nil)
    }

    @Test func estimate_zeroUnits_isLegal() {
        let estimate = BookTranslationEstimate(unitCount: 0)
        #expect(estimate.unitCount == 0)
        #expect(estimate.approximateInputTokens == nil)
    }

    @Test func estimate_withTokenEstimate_isReadable() {
        let estimate = BookTranslationEstimate(
            unitCount: 12, approximateInputTokens: 50_000)
        #expect(estimate.unitCount == 12)
        #expect(estimate.approximateInputTokens == 50_000)
    }
}
