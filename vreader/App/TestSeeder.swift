// Purpose: DEBUG-only test data seeder for UI tests.
// Creates fixture BookRecord entries via the persistence layer.
//
// Key decisions:
// - Guarded by #if DEBUG — no effect in release builds.
// - Uses PersistenceActor.insertBook() for proper SwiftData integration.
// - Fixture fingerprints use deterministic SHA-256 hashes (not real file hashes).
// - File URLs use placeholder paths since readers are placeholders anyway.
// - Covers all 4 formats plus edge cases (long title, nil author, CJK, zero reading time).
//
// @coordinates-with: VReaderApp.swift, PersistenceActor.swift, BookRecord.swift

#if DEBUG

import Foundation
import SwiftData

/// Creates fixture book entries for UI testing.
enum TestSeeder {

    /// Feature #54 Phase D-1: seeds one deterministic GLOBAL content-replacement
    /// rule ("Chapter" → "Sektion") so EPUB replacement-rule application is
    /// verifiable CU-free (`--seed-replacement-rule`). Idempotent — skips if a
    /// rule with the same pattern already exists.
    static func seedReplacementRule(container: ModelContainer) async {
        let ctx = ModelContext(container)
        let pattern = "Chapter"
        let existing = (try? ctx.fetch(FetchDescriptor<ContentReplacementRule>(
            predicate: #Predicate { $0.pattern == pattern }
        ))) ?? []
        guard existing.isEmpty else { return }
        ctx.insert(ContentReplacementRule(
            pattern: pattern,
            replacement: "Sektion",
            scopeKey: "",
            enabled: true,
            order: 0,
            label: "Phase D-1 verification rule"
        ))
        try? ctx.save()
    }

    /// Seeds the database with fixture books for UI test scenarios.
    ///
    /// - Parameter persistence: The persistence actor to insert books into.
    static func seedBooks(persistence: PersistenceActor) async {
        for fixture in Self.fixtures {
            do {
                _ = try await persistence.insertBook(fixture)
            } catch {
                AppLogger.general.warning("failed to seed '\(fixture.title)': \(error)")
            }
        }
    }

    /// Seeds a single TXT book with a real file for position persistence testing.
    /// Creates a 5000-character text file in ImportedBooks/ and a matching Book record.
    static func seedPositionTest(persistence: PersistenceActor) async {
        // Clear existing data for clean state
        await clearAllBooks(persistence: persistence)

        let text = generateTestText()
        let data = Data(text.utf8)
        let hash = "0000000000000000000000000000000000000000000000000000000000f1ca5e"
        let byteCount = Int64(data.count)

        let fingerprint = DocumentFingerprint(
            contentSHA256: hash,
            fileByteCount: byteCount,
            format: .txt
        )

        // Create the file in ImportedBooks
        let booksDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportedBooks", isDirectory: true)
        try? FileManager.default.createDirectory(at: booksDir, withIntermediateDirectories: true)

        let safeName = fingerprint.canonicalKey.replacingOccurrences(of: ":", with: "_")
        let filePath = booksDir.appendingPathComponent(safeName).appendingPathExtension("txt")
        try? data.write(to: filePath)

        let provenance = ImportProvenance(
            source: .localCopy,
            importedAt: Date(),
            originalURLBookmarkData: nil
        )

        let record = BookRecord(
            fingerprintKey: fingerprint.canonicalKey,
            title: "Position Test Book",
            author: nil,
            coverImagePath: nil,
            fingerprint: fingerprint,
            provenance: provenance,
            detectedEncoding: "utf-8",
            addedAt: Date()
        )

        do {
            _ = try await persistence.insertBook(record)
        } catch {
            AppLogger.general.warning("failed to seed position test book: \(error)")
        }
    }

    /// Seeds a Markdown file with multiple headings for TOC verification testing.
    /// Generates MD content in-memory, writes to ImportedBooks/, inserts a BookRecord.
    static func seedMDWithTOC(persistence: PersistenceActor) async {
        await clearAllBooks(persistence: persistence)

        let text = generateMDWithHeadings()
        let data = Data(text.utf8)
        let hash = "0000000000000000000000000000000000000000000000000000000000c0c001"
        let byteCount = Int64(data.count)

        let fingerprint = DocumentFingerprint(
            contentSHA256: hash,
            fileByteCount: byteCount,
            format: .md
        )

        let booksDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportedBooks", isDirectory: true)
        try? FileManager.default.createDirectory(at: booksDir, withIntermediateDirectories: true)

        let safeName = fingerprint.canonicalKey.replacingOccurrences(of: ":", with: "_")
        let filePath = booksDir.appendingPathComponent(safeName).appendingPathExtension("md")
        try? data.write(to: filePath)

        let provenance = ImportProvenance(
            source: .localCopy,
            importedAt: Date(),
            originalURLBookmarkData: nil
        )

        let record = BookRecord(
            fingerprintKey: fingerprint.canonicalKey,
            title: "Test Markdown TOC",
            author: "MD Author",
            coverImagePath: nil,
            fingerprint: fingerprint,
            provenance: provenance,
            detectedEncoding: "utf-8",
            addedAt: Date()
        )

        do {
            _ = try await persistence.insertBook(record)
        } catch {
            AppLogger.general.warning("failed to seed MD TOC book: \(error)")
        }
    }

    /// Seeds a Markdown file large enough to span multiple pages at 18pt
    /// on iPhone 17 Pro Simulator, for live multi-page-advancement
    /// verification of Feature #31 (Auto page turning).
    ///
    /// Feature #45 WI-5: the existing `seedMDWithTOC` fixture paginates to a
    /// single page on the reader viewport, short-circuiting
    /// `AutoPageTurner`'s timer. This larger seed is the foundational
    /// fixture that unblocks live-advancement verification in a follow-on
    /// iteration. The load-bearing size contract is "paginates to >=2 pages
    /// at 18pt on iPhone 17 Pro's screen", enforced by
    /// `TestSeederMDMultiPagePaginationTests`; the actual byte count drifts
    /// as the fixture text is edited and is not a documented invariant.
    ///
    /// Distinct from `seedMDWithTOC` on every dimension that contributes to
    /// `DocumentFingerprint.canonicalKey` (`format:contentSHA256:byteCount`):
    /// distinct hash suffix (`...c0c002` vs `...c0c001`) AND distinct byte
    /// count. Distinctness is pinned by the live-seed test in
    /// `TestSeederMDMultiPageTests`.
    static func seedMDMultiPage(persistence: PersistenceActor) async {
        await clearAllBooks(persistence: persistence)

        let text = generateMDMultiPage()
        let data = Data(text.utf8)
        let hash = "0000000000000000000000000000000000000000000000000000000000c0c002"
        let byteCount = Int64(data.count)

        let fingerprint = DocumentFingerprint(
            contentSHA256: hash,
            fileByteCount: byteCount,
            format: .md
        )

        let booksDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportedBooks", isDirectory: true)
        try? FileManager.default.createDirectory(at: booksDir, withIntermediateDirectories: true)

        let safeName = fingerprint.canonicalKey.replacingOccurrences(of: ":", with: "_")
        let filePath = booksDir.appendingPathComponent(safeName).appendingPathExtension("md")
        try? data.write(to: filePath)

        let provenance = ImportProvenance(
            source: .localCopy,
            importedAt: Date(),
            originalURLBookmarkData: nil
        )

        let record = BookRecord(
            fingerprintKey: fingerprint.canonicalKey,
            title: "Test Markdown Multi-Page",
            author: "MD Author",
            coverImagePath: nil,
            fingerprint: fingerprint,
            provenance: provenance,
            detectedEncoding: "utf-8",
            addedAt: Date()
        )

        do {
            _ = try await persistence.insertBook(record)
        } catch {
            AppLogger.general.warning("failed to seed MD multi-page book: \(error)")
        }
    }

    /// Generates Markdown content with multiple headings for TOC testing.
    ///
    /// `internal` (not `private`) so the `TestSeederMDMultiPageTests` suite
    /// can derive `seedMDWithTOC`'s fingerprint inputs dynamically rather
    /// than hardcoding a stale byte count literal that would silently drift
    /// out of sync if this helper's text changes. (Gate 4 round-1 Medium
    /// finding.) `TestSeeder` is an uninstantiable enum so the effective
    /// surface stays module-private.
    static func generateMDWithHeadings() -> String {
        """
        # Introduction

        This is a test markdown document for verifying the table of contents feature.
        The TOC panel should extract all ATX headings from this document.

        ## Chapter 1: The Beginning

        Content for the first chapter. This section tests H2 heading extraction
        and verifies the TOC shows a second-level entry.

        ## Chapter 2: The Middle

        Content for the second chapter. Multiple H2 entries should all appear
        in the TOC as separate rows.

        ### Section 2.1: A Subsection

        An H3 heading to verify nested TOC entries render at the correct level.

        ## Chapter 3: The End

        The final chapter. Tapping any TOC row should dismiss the panel and
        scroll to the corresponding heading position.
        """
    }

    /// Generates a multi-page Markdown fixture for Feature #31 verification.
    ///
    /// Sized at ~6 KB UTF-8 — well above the 5 KB pre-check threshold and
    /// validated by `TestSeederMDMultiPagePaginationTests` to paginate to
    /// ≥2 pages at 18pt against `UIScreen.main.bounds.size` on iPhone 17 Pro
    /// Simulator (393×852).
    ///
    /// Structure: 1 H1 title + 1 intro paragraph + 5 H2 chapters × 4 body
    /// paragraphs each + 3 H3 subsections sprinkled across the chapters. The
    /// shape mirrors a real chaptered book so future TOC + chapter-navigation
    /// verification tests can also use this fixture.
    ///
    /// `internal` (not `private`) so the two `TestSeederMDMultiPage*Tests`
    /// suites can call it directly without exposing seeding side effects.
    /// `TestSeeder` is an uninstantiable enum so the effective surface stays
    /// module-private.
    static func generateMDMultiPage() -> String {
        """
        # Multi-Page Test Document

        A deterministic test fixture for verifying live multi-page advancement under Auto Page Turn in the Markdown reader. The content below is structured to span multiple pages at 18-point system font on the iPhone 17 Pro Simulator's reader viewport. The unique per-chapter prose makes individual page transitions and table-of-contents navigation observable in screenshots.

        ## Chapter 1: Opening

        The story begins on a cold autumn morning at the edge of the harbor town where Adelaide first stepped off the steamer. The cobbled quay carried the smell of brine and pine tar, and the gulls wheeled overhead with sharp white wings. She paused at the customs gate, set down her single battered trunk, and looked up at the cathedral clock tower whose hands had stopped working three years before her arrival.

        Her brother had written that the post would meet her, and meet her it did, in the shape of an old grey horse hitched to a small black cart driven by a man who said almost nothing and seemed to know exactly where to take a stranger. The road wound inland through low yellow fields and clumps of stunted oaks, and the harbor town receded behind them like a tide drawing back from a bright stone shore.

        ### Section 1.1: A first observation

        Adelaide noticed, as she rode, that no two milestones along this road were carved from the same kind of stone. Some were sandstone, soft and faintly orange in the slanting light, and others were a hard dark granite flecked with mica that caught the morning sun in tiny silver sparks. Each carried a number and an arrow, but the numbering pattern did not match anything she had ever seen on a map.

        She filed the observation away in the back of her mind as something to ask her brother about later, if there was a later that involved comfortable evenings by the fire with port and conversation rather than the careful, measured politeness she suspected she would meet at the house. The horse plodded on. The light shifted from gold to a clean cool white as the cart climbed a long shallow ridge toward the inland valley.

        ## Chapter 2: Development

        The inland valley opened below them as the cart crested the ridge, and Adelaide saw for the first time the country she had only known from her brother's careful pen-and-ink sketches. A wide river ran a slow curve through the middle of it. On the eastern bank stood a cluster of stone barns and a single grey farmhouse with a steeply pitched slate roof and three crooked chimneys. The driver pointed at the farmhouse with his whip and grunted once.

        Smoke rose from the leftmost chimney, thin and almost vertical in the still air. The road descended in long lazy switchbacks. As they came down into the valley the air grew warmer and carried a faint sweet smell of cut hay and apples just past their peak. A flock of geese on the river lifted off the water together when the cart's wheels rattled across the bridge planks above them.

        ### Section 2.1: The arrival

        Her brother was waiting at the gate, much thinner than she remembered, with grey starting at his temples and a fixed careful expression that did not quite reach his eyes. He took her trunk with both hands and led her up the path between the rose-canes without speaking. The driver of the cart had already turned the old grey horse around and was clopping back up the switchback road toward the ridge.

        Inside the farmhouse the air was warm and smelled of woodsmoke and lavender. Two long-haired cats slept curled together on the wide stone hearth, and a kettle on the iron stove was just beginning to sing. Her brother set her trunk at the foot of the staircase and turned to her with that same careful expression, as if he were about to say something difficult and was carefully choosing the order of the words.

        ## Chapter 3: Complication

        Three days into her stay, Adelaide woke before dawn and found the house already moving around her. Her brother and two men she had not yet met were carrying long wooden crates down from the upstairs loft, in a chain along the steep narrow stairs and out through the kitchen door into the morning fog. They moved without speaking and with the easy coordinated rhythm of people who had done this exact work many times before.

        She stood at the upstairs landing in her dressing gown and watched. None of them looked up. The crates were unmarked and heavy enough that the men handled them in pairs. After the last one had gone out the kitchen door, her brother came back up the stairs and met her on the landing. He looked at her for a long moment and then sat down on the top step and put his head in his hands.

        ### Section 3.1: The first explanation

        He had not wanted to write any of this in letters, he said, because letters were read at the post offices and read again at the customs gates and read a third time by people whose names he did not want to write down even now. He had brought her here because there was a thing he needed her help with, a thing that was not strictly speaking illegal and was not strictly speaking dangerous, but was a thing that nobody in the valley could know was happening.

        Adelaide sat down on the step beside him. The fog was beginning to lift outside the small landing window. She could see the river through the bare branches of the apple trees, slow and dark and silver under the early light, and the far ridge where the road came down from the harbor town was just starting to show its long horizontal line against the brightening sky.

        ## Chapter 4: Climax

        By the time the harvest fair came around in the second week of October, Adelaide had learned the rhythms of the work and the names of every farmer on both sides of the river. The fair was held in the meadow at the wide bend below the bridge, with bunting and lanterns strung between three big elms, and a row of trestle tables set up for the judging of the apples and the pears and the early winter squash.

        She walked among the tables with her brother and the men who carried the crates, and they were greeted in the same easy familiar way as every other family from the valley. Nobody mentioned the crates. Nobody asked where the upstairs loft had been emptied to. The judges awarded the third-place ribbon for keeping-apples to her brother's orchard, and he accepted it with the same careful smile he had worn since the morning she arrived.

        ### Section 4.1: The fair at dusk

        As the afternoon turned to evening and the lanterns came up between the three big elms, a fiddler started playing on a small wooden stage at the meadow's eastern edge, and the children of the valley spilled out from between the trestle tables to dance in a loose untidy ring on the trampled grass. Adelaide stood near the cider barrel with the older women of the valley and listened to their easy talk about the coming winter and the price of wool in the harbor markets.

        The men who carried the crates were nowhere to be seen now. Her brother had drifted off toward the bridge with the parish clerk and the schoolmaster, the three of them talking in the low careful way of people who had known each other since they were boys. Adelaide held her cup of warm cider in both hands and watched the fiddler's bow flash silver in the lantern light, and felt for the first time in many years a particular and unfamiliar kind of peace.

        ## Chapter 5: Resolution

        Adelaide stayed through the winter and through the lambing season and through the long warm summer after that. By the second autumn she had her own room at the back of the house overlooking the orchard, and she had developed her own routes through the valley, her own small set of regular visits, her own quiet way of asking questions that did not feel like questions. The crates had stopped coming down from the loft. She did not ask why.

        On the morning of her two-year anniversary in the valley her brother left a small wrapped parcel on the kitchen table beside her teacup. Inside it was a single milestone fragment, sandstone, faintly orange, with a chipped corner and a number carved into one face that was the same number she had been looking for since the first day of the cart ride inland. He had found it for her. She set it on the windowsill and watched the morning light move across it.

        ### Section 5.1: A letter unfinished

        That same evening she sat down at the small writing desk in her room and began composing a letter to a friend in the harbor town. The letter began with a description of the milestone fragment and the morning light moving across it, and went on through the lambing season and the second harvest fair and the easy quiet of the second autumn. She wrote three pages and then set the pen down and looked out the window at the long flat fields turning slowly gold under the late-October sun.

        She did not finish the letter that evening, or the next, or the next. By the time she came back to it a month later, three of its details had grown stale and one of its small jokes no longer made any sense, and she set it aside and never quite got around to picking it up again. But she kept the milestone fragment on the windowsill for the rest of her life, and she never once asked her brother where the crates had gone or what had been inside them.
        """
    }

    /// Seeds War and Peace as a real TXT file (chaptered) for chapter-mode testing.
    /// Copies the DebugFixtures bundle resource to ImportedBooks/ and inserts a BookRecord.
    static func seedWarAndPeace(persistence: PersistenceActor) async {
        await clearAllBooks(persistence: persistence)

        guard let bundleURL = Bundle.main.url(
            forResource: "war-and-peace",
            withExtension: "txt",
            subdirectory: "DebugFixtures"
        ) else {
            AppLogger.general.warning("war-and-peace.txt not found in DebugFixtures bundle")
            return
        }

        guard let data = try? Data(contentsOf: bundleURL) else {
            AppLogger.general.warning("failed to read war-and-peace.txt from bundle")
            return
        }

        let hash = "0000000000000000000000000000000000000000000000000000000000beef01"
        let fingerprint = DocumentFingerprint(
            contentSHA256: hash,
            fileByteCount: Int64(data.count),
            format: .txt
        )

        let booksDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportedBooks", isDirectory: true)
        try? FileManager.default.createDirectory(at: booksDir, withIntermediateDirectories: true)

        let safeName = fingerprint.canonicalKey.replacingOccurrences(of: ":", with: "_")
        let filePath = booksDir.appendingPathComponent(safeName).appendingPathExtension("txt")
        try? data.write(to: filePath)

        let provenance = ImportProvenance(
            source: .localCopy,
            importedAt: Date(),
            originalURLBookmarkData: nil
        )
        let record = BookRecord(
            fingerprintKey: fingerprint.canonicalKey,
            title: "War and Peace",
            author: "Leo Tolstoy",
            coverImagePath: nil,
            fingerprint: fingerprint,
            provenance: provenance,
            detectedEncoding: "utf-8",
            addedAt: Date()
        )

        do {
            _ = try await persistence.insertBook(record)
        } catch {
            AppLogger.general.warning("failed to seed war-and-peace: \(error)")
        }
    }

    /// Seeds the bundled `mini-epub3.epub` fixture as a real, openable EPUB.
    /// Copies the DebugFixtures bundle resource into `ImportedBooks/` and
    /// inserts a matching `BookRecord` so the book opens into the EPUB
    /// reader.
    ///
    /// Bug #214 / GH #834: the `.books` seed's EPUB fixtures are
    /// metadata-only (`makeRecord` writes no backing file), so tapping
    /// them never opens the EPUB reader — the same Bug #209 Cause-A defect
    /// that motivated `seedTwoBooks` for TXT. This is the EPUB equivalent:
    /// a single openable EPUB so the EPUB reader bottom-chrome verification
    /// test can exercise the real reader screen. The reader resolves the
    /// file by `fingerprintKey` (see `ReaderContainerView.resolvedFileURL`),
    /// so the faked SHA-256 hash is harmless — the path is derived from the
    /// canonical key, not re-hashed.
    static func seedMiniEPUB(persistence: PersistenceActor) async {
        await clearAllBooks(persistence: persistence)

        guard let bundleURL = Bundle.main.url(
            forResource: "mini-epub3",
            withExtension: "epub",
            subdirectory: "DebugFixtures"
        ) else {
            AppLogger.general.warning("mini-epub3.epub not found in DebugFixtures bundle")
            return
        }

        guard let data = try? Data(contentsOf: bundleURL) else {
            AppLogger.general.warning("failed to read mini-epub3.epub from bundle")
            return
        }

        let hash = "00000000000000000000000000000000000000000000000000000000e9b00001"
        let fingerprint = DocumentFingerprint(
            contentSHA256: hash,
            fileByteCount: Int64(data.count),
            format: .epub
        )

        let booksDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportedBooks", isDirectory: true)
        try? FileManager.default.createDirectory(at: booksDir, withIntermediateDirectories: true)

        let safeName = fingerprint.canonicalKey.replacingOccurrences(of: ":", with: "_")
        let filePath = booksDir.appendingPathComponent(safeName).appendingPathExtension("epub")
        try? data.write(to: filePath)

        let provenance = ImportProvenance(
            source: .localCopy,
            importedAt: Date(),
            originalURLBookmarkData: nil
        )
        let record = BookRecord(
            fingerprintKey: fingerprint.canonicalKey,
            title: "Mini EPUB Fixture",
            author: "VReader Tests",
            coverImagePath: nil,
            fingerprint: fingerprint,
            provenance: provenance,
            detectedEncoding: nil,
            addedAt: Date()
        )

        do {
            _ = try await persistence.insertBook(record)
        } catch {
            AppLogger.general.warning("failed to seed mini-epub3: \(error)")
        }
    }

    /// Seeds the bundled `multi-chapter-epub.epub` fixture (4 viewport-tall
    /// chapters) as a real, openable EPUB. Bug #1561 / Feature #85: the launch-arg
    /// analogue of the DebugBridge `multi-chapter-epub` seed, so an XCUITest can
    /// drive a REAL cross-chapter scroll in the legacy #71 continuous-stitch path
    /// (the DebugBridge openurl seed is flaky on this host). Mirrors `seedMiniEPUB`;
    /// the reader resolves the file by `fingerprintKey`, so the synthetic SHA is
    /// harmless.
    static func seedMultiChapterEPUB(persistence: PersistenceActor) async {
        await clearAllBooks(persistence: persistence)

        guard let bundleURL = Bundle.main.url(
            forResource: "multi-chapter-epub",
            withExtension: "epub",
            subdirectory: "DebugFixtures"
        ) else {
            AppLogger.general.warning("multi-chapter-epub.epub not found in DebugFixtures bundle")
            return
        }

        guard let data = try? Data(contentsOf: bundleURL) else {
            AppLogger.general.warning("failed to read multi-chapter-epub.epub from bundle")
            return
        }

        let hash = "00000000000000000000000000000000000000000000000000000000e9bcc001"
        let fingerprint = DocumentFingerprint(
            contentSHA256: hash,
            fileByteCount: Int64(data.count),
            format: .epub
        )

        let booksDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportedBooks", isDirectory: true)
        try? FileManager.default.createDirectory(at: booksDir, withIntermediateDirectories: true)

        let safeName = fingerprint.canonicalKey.replacingOccurrences(of: ":", with: "_")
        let filePath = booksDir.appendingPathComponent(safeName).appendingPathExtension("epub")
        try? data.write(to: filePath)

        let provenance = ImportProvenance(
            source: .localCopy,
            importedAt: Date(),
            originalURLBookmarkData: nil
        )
        let record = BookRecord(
            fingerprintKey: fingerprint.canonicalKey,
            title: "Multi-Chapter EPUB Fixture",
            author: "VReader Tests",
            coverImagePath: nil,
            fingerprint: fingerprint,
            provenance: provenance,
            detectedEncoding: nil,
            addedAt: Date()
        )

        do {
            _ = try await persistence.insertBook(record)
        } catch {
            AppLogger.general.warning("failed to seed multi-chapter-epub: \(error)")
        }
    }

    /// Seeds a single real, openable AZW3 book — the bundled `mini-azw3.azw3`
    /// (Project Gutenberg #1064, "The Masque of the Red Death").
    ///
    /// Bug #233 / GH #964: the XCUITest `launchApp(seed:)` helper had no
    /// `TestSeedState` that opens a Foliate-rendered (AZW3/MOBI) book, which
    /// blocked CU-free verification of feature #57 (AZW3/MOBI TTS). This is
    /// the AZW3 equivalent of `seedMiniEPUB` (Bug #214 / GH #834): a single
    /// openable AZW3 so a verification test can exercise the real Foliate
    /// reader screen. The reader resolves the file by `fingerprintKey` (see
    /// `ReaderContainerView.resolvedFileURL`), so the faked SHA-256 hash is
    /// harmless — the path is derived from the canonical key, not re-hashed.
    /// The hash literal is distinct from `seedMiniEPUB`'s so the two
    /// fixtures never collide on `DocumentFingerprint.canonicalKey`.
    static func seedMiniAZW3(persistence: PersistenceActor) async {
        await clearAllBooks(persistence: persistence)

        guard let bundleURL = Bundle.main.url(
            forResource: "mini-azw3",
            withExtension: "azw3",
            subdirectory: "DebugFixtures"
        ) else {
            AppLogger.general.warning("mini-azw3.azw3 not found in DebugFixtures bundle")
            return
        }

        guard let data = try? Data(contentsOf: bundleURL) else {
            AppLogger.general.warning("failed to read mini-azw3.azw3 from bundle")
            return
        }

        let hash = "00000000000000000000000000000000000000000000000000000000a2730001"
        let fingerprint = DocumentFingerprint(
            contentSHA256: hash,
            fileByteCount: Int64(data.count),
            format: .azw3
        )

        let booksDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportedBooks", isDirectory: true)

        // Bug #233 / GH #964 (Codex Gate-4 Medium): the backing-file writes
        // are checked, not `try?`. If directory creation or the file write
        // fails, return BEFORE inserting the record — otherwise the harness
        // would see an AZW3 row with no backing file and the Foliate reader
        // couldn't open it, recreating the exact "row exists but won't open"
        // failure mode this seed is meant to avoid.
        let safeName = fingerprint.canonicalKey.replacingOccurrences(of: ":", with: "_")
        let filePath = booksDir.appendingPathComponent(safeName).appendingPathExtension("azw3")
        do {
            try FileManager.default.createDirectory(at: booksDir, withIntermediateDirectories: true)
            try data.write(to: filePath)
        } catch {
            AppLogger.general.warning("failed to write mini-azw3 backing file: \(error)")
            return
        }

        let provenance = ImportProvenance(
            source: .localCopy,
            importedAt: Date(),
            originalURLBookmarkData: nil
        )
        let record = BookRecord(
            fingerprintKey: fingerprint.canonicalKey,
            title: "Mini AZW3 Fixture",
            author: "VReader Tests",
            coverImagePath: nil,
            fingerprint: fingerprint,
            provenance: provenance,
            detectedEncoding: nil,
            addedAt: Date()
        )

        do {
            _ = try await persistence.insertBook(record)
        } catch {
            AppLogger.general.warning("failed to seed mini-azw3: \(error)")
        }
    }

    /// Bug #325: seeds the synthetic divider-structured AZW3 (`divider-azw3.azw3`,
    /// Calibre-built from a hand-authored EPUB) as a NATIVE `.azw3` — bypassing
    /// the importer's convert-on-import, so it routes to the Foliate windowed
    /// scroller (not Readium) for the cross-section windowed-scroll repro. Its
    /// spine alternates heading-only "PART ONE"/"PART TWO" divider sections
    /// (shorter than a viewport) with long content sections. Mirrors `seedMiniAZW3`.
    static func seedDividerAZW3(persistence: PersistenceActor) async {
        await clearAllBooks(persistence: persistence)

        guard let bundleURL = Bundle.main.url(
            forResource: "divider-azw3", withExtension: "azw3", subdirectory: "DebugFixtures"
        ) else {
            AppLogger.general.warning("divider-azw3.azw3 not found in DebugFixtures bundle")
            return
        }
        guard let data = try? Data(contentsOf: bundleURL) else {
            AppLogger.general.warning("failed to read divider-azw3.azw3 from bundle")
            return
        }

        let hash = "00000000000000000000000000000000000000000000000000000000a2730325"
        let fingerprint = DocumentFingerprint(
            contentSHA256: hash, fileByteCount: Int64(data.count), format: .azw3)

        let booksDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportedBooks", isDirectory: true)
        let safeName = fingerprint.canonicalKey.replacingOccurrences(of: ":", with: "_")
        let filePath = booksDir.appendingPathComponent(safeName).appendingPathExtension("azw3")
        do {
            try FileManager.default.createDirectory(at: booksDir, withIntermediateDirectories: true)
            try data.write(to: filePath)
        } catch {
            AppLogger.general.warning("failed to write divider-azw3 backing file: \(error)")
            return
        }

        let provenance = ImportProvenance(source: .localCopy, importedAt: Date(), originalURLBookmarkData: nil)
        let record = BookRecord(
            fingerprintKey: fingerprint.canonicalKey,
            title: "Divider AZW3 Fixture", author: "VReader Tests", coverImagePath: nil,
            fingerprint: fingerprint, provenance: provenance, detectedEncoding: nil, addedAt: Date())
        do {
            _ = try await persistence.insertBook(record)
        } catch {
            AppLogger.general.warning("failed to seed divider-azw3: \(error)")
        }
    }

    /// Seeds two real-file TXT books for Feature #37's per-book-settings
    /// isolation test, which needs two distinct *openable* books. The
    /// `.books` seed's fixtures are metadata-only (no backing file) and
    /// fail to open with "The file could not be found" — Bug #209 / GH #804.
    static func seedTwoBooks(persistence: PersistenceActor) async {
        await clearAllBooks(persistence: persistence)
        clearPerBookSettings()
        let baseDate = Date(timeIntervalSinceReferenceDate: 700_000_000)
        await insertRealTXTBook(
            persistence: persistence,
            title: "Per-Book Settings Test One",
            sha256Suffix: "b0010001",
            text: generateTestText(),
            addedAt: baseDate
        )
        await insertRealTXTBook(
            persistence: persistence,
            title: "Per-Book Settings Test Two",
            sha256Suffix: "b0020002",
            text: generateTestText() + "\n\nSecond book — distinct content for a distinct fingerprint.",
            addedAt: baseDate.addingTimeInterval(3600)
        )
    }

    /// Writes one real TXT file to `ImportedBooks/` and inserts a matching
    /// `BookRecord`, so the book opens into a working reader. Used by
    /// `seedTwoBooks`; mirrors the file-write path of `seedPositionTest`.
    private static func insertRealTXTBook(
        persistence: PersistenceActor,
        title: String,
        sha256Suffix: String,
        text: String,
        addedAt: Date
    ) async {
        let data = Data(text.utf8)
        let paddedHash = String(repeating: "0", count: max(0, 64 - sha256Suffix.count))
            + sha256Suffix.lowercased()
        let hash = String(paddedHash.suffix(64))
        let fingerprint = DocumentFingerprint(
            contentSHA256: hash,
            fileByteCount: Int64(data.count),
            format: .txt
        )
        let booksDir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ImportedBooks", isDirectory: true)
        let safeName = fingerprint.canonicalKey.replacingOccurrences(of: ":", with: "_")
        let filePath = booksDir.appendingPathComponent(safeName).appendingPathExtension("txt")
        do {
            // Bug #209 / GH #804 (Codex audit): fail fast — if the backing
            // file is not written, do NOT fall through to `insertBook`.
            // Metadata without a file reproduces the very "file could not
            // be found" open failure this seed exists to prevent.
            try FileManager.default.createDirectory(at: booksDir, withIntermediateDirectories: true)
            try data.write(to: filePath)
        } catch {
            AppLogger.general.warning("failed to write seed TXT file for '\(title)': \(error)")
            return
        }
        let provenance = ImportProvenance(
            source: .localCopy,
            importedAt: addedAt,
            originalURLBookmarkData: nil
        )
        let record = BookRecord(
            fingerprintKey: fingerprint.canonicalKey,
            title: title,
            author: nil,
            coverImagePath: nil,
            fingerprint: fingerprint,
            provenance: provenance,
            detectedEncoding: "utf-8",
            addedAt: addedAt
        )
        do {
            _ = try await persistence.insertBook(record)
        } catch {
            AppLogger.general.warning("failed to seed real TXT book '\(title)': \(error)")
        }
    }

    /// Removes the file-backed per-book settings overrides. Bug #209 /
    /// GH #804 (Codex audit): `clearKnownPreferences` wipes only
    /// UserDefaults, but per-book overrides are JSON files under
    /// `Application Support/PerBookSettings` (see
    /// `ReaderContainerView.perBookSettingsBaseURL`). Feature #37's
    /// isolation / persistence tests reopen books with fixed fingerprint
    /// keys, so a leftover override from a prior run would make the
    /// "toggle starts OFF" assertions nondeterministic. `seedTwoBooks`
    /// clears the directory so every run starts from a known-empty state.
    private static func clearPerBookSettings() {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PerBookSettings", isDirectory: true)
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        do {
            try FileManager.default.removeItem(at: dir)
        } catch {
            AppLogger.general.warning("failed to clear PerBookSettings: \(error)")
        }
    }

    /// Generates ~5000 characters of scrollable test content with numbered paragraphs.
    private static func generateTestText() -> String {
        var lines: [String] = []
        lines.append("Position Persistence Test Document")
        lines.append("")
        for i in 1...100 {
            lines.append("Paragraph \(i): This is test content for verifying reading position persistence. The reader should remember where you stopped reading and restore the scroll position when reopened.")
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Deletes all books from the database for a clean test state.
    ///
    /// - Parameter persistence: The persistence actor to clear.
    static func clearAllBooks(persistence: PersistenceActor) async {
        do {
            let books = try await persistence.fetchAllLibraryBooks()
            for book in books {
                try await persistence.deleteBook(fingerprintKey: book.fingerprintKey)
            }
        } catch {
            AppLogger.general.warning("failed to clear books: \(error)")
        }
    }

    /// UserDefaults keys that production code persists app-state to.
    /// Bug #152 (GH #426): `--uitesting` swaps the SwiftData store for
    /// in-memory but UserDefaults survives across `XCUIApplication.launch()`
    /// cycles, so empty-state UI assertions flake based on residual
    /// state from prior simulator sessions. The `--reset-preferences`
    /// launch arg invokes `clearKnownPreferences(in:)` to wipe this list.
    ///
    /// Keep this list aligned with where each subsystem persists. New
    /// UserDefaults keys added to production code should be reflected
    /// here so empty-state tests stay deterministic.
    static let knownPreferenceKeys: [String] = [
        // Library
        "library.sortOrder",
        "library.viewMode",
        // Reader (mirrors BackupSettingsKeys.all + tap zones)
        "readerTheme",
        "readerTypography",
        "readerUseCustomBackground",
        "readerBackgroundOpacity",
        "readerEPUBLayout",
        "readerAutoPageTurn",
        "readerAutoPageTurnInterval",
        "readerPageTurnAnimation",
        "readerChineseConversion",
        "readerTapZoneConfig",
        // OPDS
        "opds.savedCatalogs",
        // HTTP TTS
        "httpTTSConfig",
        // AI
        "com.vreader.ai.configuration",
        "com.vreader.ai.consentGranted",
        "com.vreader.ai.consentDate",
        // WebDAV
        "com.vreader.webdav.wifiOnly",
        // WebDAV multi-profile (#52 WI-1 / WI-2 / WI-5):
        // - JSON-encoded `[WebDAVServerProfile]` written by
        //   `WebDAVServerProfileStore`
        // - The active profile's UUID (hyphenated string)
        // - The WI-2 one-shot migration marker (kept in this list so
        //   `--reset-preferences` re-arms the migrator for tests that
        //   need to exercise the legacy-flat → "Default"-profile flow
        //   again from a clean state)
        "com.vreader.webdav.profiles",
        "com.vreader.webdav.activeProfileID",
        "com.vreader.webdav.profilesMigrated.v1",
    ]

    /// Removes every key in `knownPreferenceKeys` from the supplied
    /// `UserDefaults`. Idempotent — keys that don't exist are skipped.
    /// Bug #152 / GH #426 fix.
    ///
    /// - Parameter defaults: The store to wipe. Defaults to
    ///   `UserDefaults.standard` so production callers don't need to
    ///   know which store the app reads from. Tests can pass a
    ///   purpose-built `UserDefaults(suiteName:)` to avoid touching
    ///   the host's real preferences.
    static func clearKnownPreferences(in defaults: UserDefaults = .standard) {
        for key in knownPreferenceKeys {
            defaults.removeObject(forKey: key)
        }
    }

    // MARK: - Fixture Data

    /// All fixture book records for seeding.
    ///
    /// SHA-256 suffixes use only valid hex chars (0-9, a-f) to pass
    /// DocumentFingerprint validation.
    /// Fixed dates ensure deterministic ordering across test runs.
    static let fixtures: [BookRecord] = {
        // Base date: 2024-03-01 00:00:00 UTC (700_000_000 seconds since reference date)
        let baseDate = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let increment: TimeInterval = 3600 // 1 hour between fixtures

        return [
            // Standard format fixtures
            makeRecord(
                format: .epub,
                sha256Suffix: "e00b0001",
                title: "Test EPUB Book",
                author: "Test Author",
                byteCount: 102_400,
                date: baseDate
            ),
            makeRecord(
                format: .pdf,
                sha256Suffix: "0df00001",
                title: "Test PDF Document",
                author: "PDF Author",
                byteCount: 204_800,
                date: baseDate.addingTimeInterval(increment)
            ),
            makeRecord(
                format: .txt,
                sha256Suffix: "00a00001",
                title: "Test Plain Text",
                author: nil,
                byteCount: 1_024,
                date: baseDate.addingTimeInterval(increment * 2)
            ),
            makeRecord(
                format: .md,
                sha256Suffix: "0d000001",
                title: "Test Markdown",
                author: "MD Author",
                byteCount: 2_048,
                date: baseDate.addingTimeInterval(increment * 3)
            ),

            // Edge case: long title
            makeRecord(
                format: .txt,
                sha256Suffix: "10face01",
                title: "A Very Long Book Title That Should Definitely Trigger Truncation in Both Grid and List Modes",
                author: "Author Name",
                byteCount: 512,
                date: baseDate.addingTimeInterval(increment * 4)
            ),

            // Edge case: CJK title
            makeRecord(
                format: .txt,
                sha256Suffix: "c0a00001",
                title: "中文日本語한국어",
                author: nil,
                byteCount: 768,
                date: baseDate.addingTimeInterval(increment * 5)
            ),

            // Edge case: zero reading time (unread book)
            makeRecord(
                format: .epub,
                sha256Suffix: "00dead01",
                title: "Unread Book",
                author: "Author",
                byteCount: 51_200,
                date: baseDate.addingTimeInterval(increment * 6)
            ),

            // Edge case: password-protected PDF placeholder
            makeRecord(
                format: .pdf,
                sha256Suffix: "0bead001",
                title: "Protected PDF",
                author: nil,
                byteCount: 307_200,
                date: baseDate.addingTimeInterval(increment * 7)
            ),
        ]
    }()

    // MARK: - Private Helpers

    /// Creates a deterministic BookRecord for testing.
    ///
    /// SHA-256 is faked: 56 zeros + the suffix, padded to 64 hex chars.
    /// This is not a real hash but satisfies DocumentFingerprint validation.
    private static func makeRecord(
        format: BookFormat,
        sha256Suffix: String,
        title: String,
        author: String?,
        byteCount: Int64,
        date: Date
    ) -> BookRecord {
        // Pad suffix to create a valid 64-char lowercase hex string
        let paddedHash = String(repeating: "0", count: max(0, 64 - sha256Suffix.count))
            + sha256Suffix.lowercased()
        let hash = String(paddedHash.suffix(64))

        // DocumentFingerprint.validated returns nil if hash is invalid
        // For test fixtures, we construct directly since we control the hash format
        let fingerprint = DocumentFingerprint(
            contentSHA256: hash,
            fileByteCount: byteCount,
            format: format
        )

        let provenance = ImportProvenance(
            source: .localCopy,
            importedAt: date,
            originalURLBookmarkData: nil
        )

        return BookRecord(
            fingerprintKey: fingerprint.canonicalKey,
            title: title,
            author: author,
            coverImagePath: nil,
            fingerprint: fingerprint,
            provenance: provenance,
            detectedEncoding: format == .txt ? "utf-8" : nil,
            addedAt: date
        )
    }
}

#endif
