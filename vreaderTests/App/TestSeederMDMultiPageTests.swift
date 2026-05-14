// Purpose: Tests for Feature #45 WI-5's `TestSeeder.generateMDMultiPage()`
// fixture — a larger MD doc sized to span multiple pages at 18pt on iPhone 17
// Pro Simulator. This file covers the cheap structural checks (byte count,
// chapter shape, fingerprint distinctness); the load-bearing pagination
// assertion against the real MD render pipeline lives in
// `TestSeederMDMultiPagePaginationTests`.

import Testing
import Foundation
import SwiftData
@testable import vreader

#if DEBUG

@Suite("TestSeeder.seedMDMultiPage")
struct TestSeederMDMultiPageTests {

    /// Cheap pre-check: the fixture is large enough that the rendered output
    /// has a chance of spanning multiple pages at 18pt. The load-bearing
    /// gate is `TestSeederMDMultiPagePaginationTests`; this is just the
    /// regression net for "someone trimmed the filler and the fixture is
    /// back to the seedMDWithTOC size class".
    @Test func generatedContentExceeds5KBThreshold() {
        let text = TestSeeder.generateMDMultiPage()
        let byteCount = text.utf8.count
        #expect(byteCount > 5_000, "expected >5000 bytes, got \(byteCount)")
    }

    /// The fixture's plan-doc contract is 5 H2 chapters. Catches regression
    /// that collapses chapter structure (which would also affect any future
    /// TOC or chapter-navigation tests that use this fixture).
    @Test func generatedContentHasAtLeast5H2ChapterHeadings() {
        let text = TestSeeder.generateMDMultiPage()
        let chapterCount = text.components(separatedBy: "\n## Chapter ").count - 1
        #expect(chapterCount >= 5, "expected >=5 '## Chapter' headings, got \(chapterCount)")
    }

    /// Pins the actual collision contract: `DocumentFingerprint.canonicalKey`
    /// is `format:contentSHA256:fileByteCount`. The two MD seeds must produce
    /// distinct canonical keys when both are actually exercised.
    ///
    /// The test runs each seed function against a disposable in-memory
    /// SwiftData store and reads the persisted `fingerprintKey` back —
    /// proving distinctness against the LIVE seed implementations, not just
    /// reconstructed fingerprint inputs. If a future contributor accidentally
    /// gives the two seed functions the same hash literal (or same byte
    /// count + format), this test fails immediately with a clear signal.
    /// (Gate 4 round-2 Medium finding fix.)
    @Test func seedMDMultiPageAndSeedMDWithTOCProduceDistinctCanonicalKeysWhenLiveSeeded() async throws {
        let schema = Schema(SchemaV6.models)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let persistence = PersistenceActor(modelContainer: container)

        await TestSeeder.seedMDWithTOC(persistence: persistence)
        let tocBooks = try await persistence.fetchAllLibraryBooks()
        let tocKey = tocBooks.first?.fingerprintKey
        #expect(tocKey != nil)

        await TestSeeder.seedMDMultiPage(persistence: persistence)
        let multiPageBooks = try await persistence.fetchAllLibraryBooks()
        let multiPageKey = multiPageBooks.first?.fingerprintKey
        #expect(multiPageKey != nil)

        #expect(tocKey != multiPageKey,
                "seedMDWithTOC and seedMDMultiPage produced identical canonicalKey '\(tocKey ?? "nil")' — distinctness regression")
    }
}

#endif
