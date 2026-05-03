// Purpose: Tests for the background-event handler bridge between iOS's
// `application(_:handleEventsForBackgroundURLSession:completionHandler:)`,
// `VReaderAppDelegate`, and the lazy-download coordinator. Feature #47
// WI-3b. iOS will not release the app's background-launch grace period
// until the handler runs, so dropping it leaks battery and orphans
// pending events.

import Testing
import Foundation
@testable import vreader

@MainActor
@Suite("VReaderAppDelegate — background event handler storage")
struct VReaderAppDelegateTests {

    @Test func takeBackgroundHandler_unknownIdentifier_returnsNil() {
        let id = UUID().uuidString
        #expect(VReaderAppDelegate.takeBackgroundHandler(for: id) == nil)
    }

    @Test func storeAndRetrieve_returnsSameHandler() async {
        let id = UUID().uuidString
        var didFire = false
        VReaderAppDelegate.backgroundCompletionHandlers[id] = { didFire = true }
        let handler = VReaderAppDelegate.takeBackgroundHandler(for: id)
        #expect(handler != nil)
        handler?()
        #expect(didFire)
        // Removed after take.
        #expect(VReaderAppDelegate.backgroundCompletionHandlers[id] == nil)
    }

    @Test func multipleSessionIdentifiers_storedIndependently() {
        let idA = UUID().uuidString
        let idB = UUID().uuidString
        var firedA = false
        var firedB = false
        VReaderAppDelegate.backgroundCompletionHandlers[idA] = { firedA = true }
        VReaderAppDelegate.backgroundCompletionHandlers[idB] = { firedB = true }

        VReaderAppDelegate.takeBackgroundHandler(for: idA)?()
        #expect(firedA)
        #expect(firedB == false)

        VReaderAppDelegate.takeBackgroundHandler(for: idB)?()
        #expect(firedB)
    }

    @Test func storeBackgroundHandler_duplicateIdentifier_invokesPreviousBeforeReplace() {
        // iOS shouldn't deliver two handoffs for the same session
        // identifier, but if it does, dropping the previous handler
        // would leak iOS's background-launch grace period for that run.
        // The store must invoke the previous handler before overwriting.
        let id = UUID().uuidString
        var firedFirst = false
        var firedSecond = false
        VReaderAppDelegate.storeBackgroundHandler({ firedFirst = true }, for: id)
        VReaderAppDelegate.storeBackgroundHandler({ firedSecond = true }, for: id)
        // First handler invoked during replace.
        #expect(firedFirst)
        // Second handler stored, awaiting urlSessionDidFinishEvents.
        #expect(firedSecond == false)
        VReaderAppDelegate.takeBackgroundHandler(for: id)?()
        #expect(firedSecond)
    }
}

@MainActor
@Suite("LazyDownloadCoordinator.didFinishBackgroundEvents")
struct LazyDownloadBackgroundEventsTests {

    @Test func invokesProvidedHandler() {
        let coord = LazyDownloadCoordinator()
        var fired = false
        coord.didFinishBackgroundEvents(
            sessionIdentifier: "com.test.session",
            handlerProvider: { id in
                #expect(id == "com.test.session")
                return { fired = true }
            }
        )
        #expect(fired)
    }

    @Test func missingHandler_doesNotCrash() {
        let coord = LazyDownloadCoordinator()
        // Foreground events arriving without a fresh app-launch handoff
        // is normal — the no-op path must not assert/crash.
        coord.didFinishBackgroundEvents(
            sessionIdentifier: "no.such.session",
            handlerProvider: { _ in nil }
        )
    }

    @Test func handlerIsInvokedExactlyOnce() {
        let coord = LazyDownloadCoordinator()
        var fireCount = 0
        coord.didFinishBackgroundEvents(
            sessionIdentifier: "x",
            handlerProvider: { _ in { fireCount += 1 } }
        )
        #expect(fireCount == 1)
    }

    @Test func defaultProvider_readsFromAppDelegate() {
        // Without `handlerProvider`, the coordinator must consult
        // `VReaderAppDelegate.takeBackgroundHandler(for:)` — the
        // production wiring iOS uses to release background grace.
        let id = "com.vreader.test.session.\(UUID().uuidString)"
        var fired = false
        VReaderAppDelegate.backgroundCompletionHandlers[id] = { fired = true }

        let coord = LazyDownloadCoordinator()
        coord.didFinishBackgroundEvents(sessionIdentifier: id)

        #expect(fired)
        // Handler removed after invocation so a second event doesn't
        // double-fire it.
        #expect(VReaderAppDelegate.backgroundCompletionHandlers[id] == nil)
    }
}
