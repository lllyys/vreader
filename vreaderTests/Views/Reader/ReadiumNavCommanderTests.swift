// Purpose: Feature #42 Phase 1 WI-9a — unit tests for `ReadiumNavCommander`,
// the host→coordinator navigation sink. Pins the bind / fire / clear lifecycle
// (the seam the host's page-turn / jump `.onReceive` observers drive) WITHOUT a
// live `EPUBNavigatorViewController` — the actual navigator `goForward` /
// `goBackward` / `go(to:)` dispatch is device-verified (the concrete navigator
// has no protocol seam to fake).
//
// @coordinates-with vreader/Views/Reader/ReadiumEPUBHost+Navigation.swift

#if canImport(UIKit)
import Testing
import Foundation
import ReadiumShared
@testable import vreader

@MainActor
@Suite("ReadiumNavCommander (WI-9a)")
struct ReadiumNavCommanderTests {

    private func makeLocator() -> ReadiumShared.Locator {
        ReadiumShared.Locator(
            href: RelativeURL(path: "ch1.xhtml")!,
            mediaType: .xhtml,
            locations: .init(progression: 0.5)
        )
    }

    @Test func boundHandlers_fireOnIntent() {
        let commander = ReadiumNavCommander()
        var nextCount = 0
        var prevCount = 0
        var navigatedHrefs: [String] = []
        var clearCount = 0
        commander.bind(
            next: { nextCount += 1 },
            previous: { prevCount += 1 },
            navigate: { navigatedHrefs.append($0.href.string) },
            clearSelection: { clearCount += 1 }
        )

        commander.nextPage()
        commander.nextPage()
        commander.previousPage()
        commander.navigate(to: makeLocator())
        commander.clearSelection()

        #expect(nextCount == 2)
        #expect(prevCount == 1)
        #expect(navigatedHrefs == ["ch1.xhtml"])
        #expect(clearCount == 1)
    }

    @Test func unbound_intentsNoOp() {
        // Before any `attach` binding (or after `clear`), firing an intent must
        // not crash and must not invoke anything — the guard against a late
        // notification reaching a torn-down navigator.
        let commander = ReadiumNavCommander()
        commander.nextPage()
        commander.previousPage()
        commander.navigate(to: makeLocator())
        commander.clearSelection()
        // Reaching here without a crash is the assertion.
        #expect(Bool(true))
    }

    @Test func clear_dropsHandlers() {
        let commander = ReadiumNavCommander()
        var fired = 0
        commander.bind(
            next: { fired += 1 },
            previous: { fired += 1 },
            navigate: { _ in fired += 1 },
            clearSelection: { fired += 1 }
        )
        commander.clear()

        commander.nextPage()
        commander.previousPage()
        commander.navigate(to: makeLocator())
        commander.clearSelection()

        #expect(fired == 0)
    }

    @Test func rebind_replacesHandlers() {
        let commander = ReadiumNavCommander()
        var firstFired = 0
        var secondFired = 0
        commander.bind(next: { firstFired += 1 }, previous: {}, navigate: { _ in }, clearSelection: {})
        commander.bind(next: { secondFired += 1 }, previous: {}, navigate: { _ in }, clearSelection: {})

        commander.nextPage()

        #expect(firstFired == 0)
        #expect(secondFired == 1)
    }
}
#endif
