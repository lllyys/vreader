// Purpose: Tests for `SelectionPopoverAction` — the payload shape emitted
// by Feature #60's SelectionPopover (WI-3). Local-dispatch only;
// intentionally NOT `Codable` (per Codex Gate 2 round 1: serialized
// payload would invite a persistence schema commitment we don't need
// for the in-view callback chain).

import Testing
import Foundation
@testable import vreader

@Suite("SelectionPopoverAction — Feature #60 WI-3")
struct SelectionPopoverActionTests {

    // MARK: - Equatable behavior

    /// The 5 design cases — highlight(yellow|pink|green|blue), note,
    /// translate, askAI, read — must compare correctly for Equatable.
    /// `.highlight(...)` distinguishes by the inner `NamedHighlightColor`.
    @Test
    func equatable_distinguishesAllCases() {
        let cases: [SelectionPopoverAction] = [
            .highlight(.yellow),
            .highlight(.pink),
            .highlight(.green),
            .highlight(.blue),
            .note,
            .translate,
            .askAI,
            .read,
        ]
        // Each case equals itself.
        for c in cases {
            #expect(c == c)
        }
        // No two distinct cases are equal.
        for i in 0..<cases.count {
            for j in 0..<cases.count where i != j {
                #expect(cases[i] != cases[j])
            }
        }
    }

    // MARK: - Exhaustive switch (the WI-7 handler will rely on this)

    /// A test that switches over every case forces the compiler to flag
    /// missing cases when the enum grows. The body asserts only that
    /// each case maps to a non-empty label — the real value is the
    /// compile-time exhaustiveness check.
    @Test
    func exhaustiveSwitch_handlesEveryCase() {
        func label(for action: SelectionPopoverAction) -> String {
            switch action {
            case .highlight(let color): return "highlight(\(color.rawValue))"
            case .note: return "note"
            case .translate: return "translate"
            case .askAI: return "askAI"
            case .read: return "read"
            }
        }
        let samples: [SelectionPopoverAction] = [
            .highlight(.yellow), .note, .translate, .askAI, .read,
        ]
        for action in samples {
            #expect(!label(for: action).isEmpty)
        }
    }

    // MARK: - Sendable (compile-time conformance check)

    /// If `SelectionPopoverAction` accidentally captures a non-Sendable
    /// associated value (e.g. a reference type) in the future, this
    /// generic helper that requires `Sendable` will fail to compile.
    @Test
    func sendable_conformance_isAvailable() {
        func requireSendable<T: Sendable>(_ value: T) -> T { value }
        let action = SelectionPopoverAction.highlight(.green)
        let echoed = requireSendable(action)
        #expect(echoed == action)
    }
}
