// Purpose: Static catalog of fixture books bundled with DEBUG builds, used by
// vreader-debug://seed (feature #44 DebugBridge). Each entry maps a stable
// fixture name to a bundle resource so automated tests have deterministic
// content to load. Adding a new fixture: drop the file into
// vreader/Resources/DebugFixtures/ and add a catalog entry here.
// DEBUG-only.

#if DEBUG

import Foundation

/// A bundled fixture book.
struct DebugFixture: Equatable {
    /// Stable identifier passed to `vreader-debug://seed?fixture=<name>`.
    let name: String
    /// Source format. Drives the importer/reader path the seeded book uses.
    let format: Format
    /// Bundle resource base name (without extension).
    let resourceName: String
    /// Bundle resource file extension (without dot).
    let resourceExtension: String

    enum Format: String, Equatable {
        case epub
        case txt
        case pdf
        case azw3
        case md
    }
}

/// Static catalog of fixture books. Single source of truth for fixture names.
enum DebugFixtureCatalog {

    /// Catalog tracks fixtures that actually ship in the DEBUG bundle.
    /// Adding a new fixture requires both (a) dropping the file in
    /// `vreader/Resources/DebugFixtures/` and registering it as a Resource,
    /// and (b) adding a row here. The bundle-existence test in
    /// `DebugFixtureCatalogTests` enforces (a).
    private static let entries: [DebugFixture] = [
        DebugFixture(name: "war-and-peace", format: .txt,  resourceName: "war-and-peace", resourceExtension: "txt"),
        DebugFixture(name: "mini-epub3",    format: .epub, resourceName: "mini-epub3",    resourceExtension: "epub"),
        // Public-domain MOBI ("The Masque of the Red Death", Edgar Allan Poe,
        // Project Gutenberg ebook 1064). Stored under the .azw3 extension
        // because vreader's `BookFormat.azw3` collapses MOBI/AZW/AZW3/PRC into
        // one importer path; Foliate-js sniffs the magic bytes at runtime.
        // 128 KB compressed. Unblocks Foliate eval device-verification (bug #143).
        DebugFixture(name: "mini-azw3",     format: .azw3, resourceName: "mini-azw3",     resourceExtension: "azw3"),
        // Feature #70 WI-4: a small synthetic Markdown fixture so the `.md`
        // reader path is automatable — needed for feature #70's final
        // 4-format (TXT/MD/EPUB/AZW3) calibration acceptance pass. The MD
        // catalog had no entry before this; the `Format.md` case already
        // existed.
        DebugFixture(name: "mini-markdown", format: .md,   resourceName: "mini-markdown", resourceExtension: "md"),
        // Bug #273: a 4-chapter EPUB whose chapters are each TALLER than a
        // viewport, so continuous-scroll navigation (feature #71 WI-8) produces
        // a measurable, distinguishable scrollTop landing — `mini-epub3`'s two
        // tiny chapters fit in roughly one screen (total scroll range ~53px),
        // so a navigate clamps to the bottom and can't be told apart. Four
        // spine items also make the out-of-window rebuild branch reachable
        // (anchor 0 → window [0,1]; navigating to chapter 3/4 is out-of-window).
        DebugFixture(name: "multi-chapter-epub", format: .epub, resourceName: "multi-chapter-epub", resourceExtension: "epub"),
        // Feature #17 (#361): a 6-page text-layer PDF so the PDF reader path is
        // CU-free seedable+openable — the catalog had no PDF before, which
        // blocked PDF render/theme verification. Generated via `cupsfilter`
        // (selectable text layer, not rasterized). Note: PDF *highlight
        // creation* still needs a real long-press-drag text selection (CU /
        // real device) — there is no UTF-16 `highlight` driver for PDF — so this
        // fixture unblocks open / render / theme verification, not the
        // gesture-driven highlight criterion.
        DebugFixture(name: "multi-page-pdf", format: .pdf, resourceName: "multi-page-pdf", resourceExtension: "pdf"),
    ]

    /// All catalog entries.
    static func all() -> [DebugFixture] {
        return entries
    }

    /// Look up a fixture by name. Returns nil for unknown or empty names.
    static func find(name: String) -> DebugFixture? {
        guard !name.isEmpty else { return nil }
        return entries.first { $0.name == name }
    }
}

#endif
