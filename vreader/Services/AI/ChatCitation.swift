// Purpose: The provenance of what an AI Chat answer drew on — the "Drew on"
// citation chips under each reply (Feature #86 WI-2+ / WI-6). Provenance-FIRST:
// `TOCEntry` has no stable chapter ordinals and Foliate/AZW3 has no AI text-load
// path, so a display-driven `chapter(Int)` would be wrong. The label is derived
// where derivable and degrades per format; the kind + optional locator/span are
// the stable record.
//
// Per-format degradation (an explicit acceptance dimension):
// - TXT/MD with a char-offset TOC → span-level chapter labels ("Ch. 1").
// - EPUB/AZW3 (no char-offset TOC / no AI text-load path) → scope-level labels
//   only ("Chapter", "Book so far"); never a fabricated ordinal.
// - PDF → page-level.
//
// @coordinates-with: ChatContextAssembler.swift, ChatCitationRow.swift (WI-6),
//   `dev-docs/designs/vreader-fidelity-v1/project/design-notes/chat-ai-scope-sources.md`

import Foundation

/// One provenance item an AI Chat answer drew on. Feature #86 WI-2+.
struct ChatCitation: Sendable, Equatable, Identifiable {
    /// What kind of source this citation names. Stable across formats.
    enum SourceKind: String, Sendable, Equatable {
        case scope          // the selected reading scope (section/chapter/book-so-far)
        case note           // a standalone note or a note attached to a highlight
        case highlight      // a text highlight
        case bookmark       // a bookmark
        case wholeBookSpan  // a span pulled by on-demand whole-book retrieval
    }

    let id: UUID
    let sourceKind: SourceKind
    /// Display label, derived where possible ("Ch. 1" / "Section" / "your note").
    let label: String
    /// Optional provenance anchor. `nil` when not derivable (e.g. EPUB no-offset TOC).
    let locator: Locator?
    /// Optional covered UTF-16 span (whole-book / scope citations). `nil` otherwise.
    let spanUTF16: ClosedRange<Int>?
    /// Optional ordinal when a stable order genuinely exists; never fabricated.
    let sequence: Int?
    /// True when this citation references text ahead of the reader's position —
    /// the amber `· ahead` spoiler flag. Only whole-book spans can be ahead.
    let aheadOfReader: Bool

    init(
        id: UUID = UUID(),
        sourceKind: SourceKind,
        label: String,
        locator: Locator? = nil,
        spanUTF16: ClosedRange<Int>? = nil,
        sequence: Int? = nil,
        aheadOfReader: Bool = false
    ) {
        self.id = id
        self.sourceKind = sourceKind
        self.label = label
        self.locator = locator
        self.spanUTF16 = spanUTF16
        self.sequence = sequence
        self.aheadOfReader = aheadOfReader
    }
}
