// Purpose: Timer-based auto page turning for the reader.
// Calls navigator.nextPage() at a configurable interval.
// Stops at the last page. Pauses on user interaction.
//
// Key decisions:
// - @MainActor + @Observable for SwiftUI binding.
// - Interval clamped to 1...60 seconds.
// - Uses Task.sleep for timer to allow clean cancellation.
// - Auto-stops when navigator reaches last page.
//
// @coordinates-with PageNavigator.swift, BasePageNavigator.swift

import Foundation

/// Timer-based auto page turning service.
@MainActor @Observable
final class AutoPageTurner {

    // MARK: - Types

    enum State: Sendable, Equatable {
        case idle
        case running
        case paused
    }

    // MARK: - Public State

    private(set) var state: State = .idle

    /// Seconds between page turns, clamped to 1...60.
    ///
    /// Bug #191: a previous shape — `var interval = 5.0 { didSet { interval =
    /// Self.clampInterval(interval) } }` — recursed infinitely under
    /// `@Observable`. The macro splits the property into a stored backing
    /// (`_interval`, where the didSet attaches) and a computed wrapper
    /// (`interval`, the public accessor). Writing to `interval` from inside
    /// `_interval.didSet` re-entered the public setter, which wrote back to
    /// `_interval`, refiring its didSet — ~23k-frame SIGSEGV stack-guard
    /// fault. Swift's "didSet doesn't re-fire from within itself" invariant
    /// only holds when the body writes to the same stored property whose
    /// didSet is running; the macro's wrapper/storage split breaks it.
    ///
    /// Fix: route through `@ObservationIgnored` raw storage plus a computed
    /// property that clamps on the way in. `access`/`withMutation` preserve
    /// SwiftUI observation tracking; no didSet means no recursion. See
    /// `docs/bugs.md` row #191 and GH #682.
    @ObservationIgnored
    private var _intervalRaw: TimeInterval = 5.0

    var interval: TimeInterval {
        get {
            access(keyPath: \.interval)
            return _intervalRaw
        }
        set {
            let clamped = Self.clampInterval(newValue)
            // Bug #191 Codex audit Low: skip `withMutation` when the clamped
            // value didn't change. Manual `withMutation` always emits an
            // observation transaction, unlike the macro-synthesized setter
            // which can short-circuit identical writes.
            guard clamped != _intervalRaw else { return }
            withMutation(keyPath: \.interval) {
                _intervalRaw = clamped
            }
        }
    }

    // MARK: - Private

    private var timerTask: Task<Void, Never>?
    private weak var navigator: (any PageNavigator)?

    // MARK: - Public API

    /// Start auto page turning using the given navigator.
    /// If already running, restarts with the current interval.
    func start(navigator: any PageNavigator) {
        stop()
        self.navigator = navigator
        state = .running
        scheduleTimer()
    }

    /// Pause auto page turning. Timer is suspended but state is retained.
    func pause() {
        guard state == .running else { return }
        timerTask?.cancel()
        timerTask = nil
        state = .paused
    }

    /// Resume auto page turning from paused state.
    func resume() {
        guard state == .paused else { return }
        state = .running
        scheduleTimer()
    }

    /// Stop auto page turning completely. Resets to idle.
    func stop() {
        timerTask?.cancel()
        timerTask = nil
        navigator = nil
        state = .idle
    }

    // MARK: - Private

    private func scheduleTimer() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let sleepInterval = self.interval
                try? await Task.sleep(for: .seconds(sleepInterval))
                guard !Task.isCancelled else { return }

                guard let nav = self.navigator else {
                    self.stop()
                    return
                }

                // Check if at last page
                if nav.currentPage >= nav.totalPages - 1 {
                    self.stop()
                    return
                }

                nav.nextPage()
            }
        }
    }

    private static func clampInterval(_ value: TimeInterval) -> TimeInterval {
        // Bug #191 Codex audit Medium: `max(1.0, min(60.0, .nan))` propagates
        // `.nan` through (NaN comparisons return false, so neither min nor
        // max replaces it). Without this guard, `Task.sleep(for: .seconds(
        // .nan))` in `scheduleTimer` hits undefined behavior. Treat any
        // non-finite input as "reset to default 5s".
        guard value.isFinite else { return 5.0 }
        return max(1.0, min(60.0, value))
    }
}
