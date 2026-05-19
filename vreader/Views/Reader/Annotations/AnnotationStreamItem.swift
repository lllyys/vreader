// Purpose: Feature #62 WI-1 — the value type unifying the two
// annotation record kinds for `HighlightsSheet`'s card stream.
//
// `HighlightsSheet` (the #860 unified-card design) renders BOTH
// `HighlightRecord` (a highlighted passage, note optional) and
// `AnnotationRecord` (a standalone note, no anchored passage) in one
// chronological stream. `AnnotationStreamItem` is the discriminated
// union the stream is built from; `HighlightAnnotationCard` switches on
// it to pick `HighlightCardV3` vs `StandaloneNoteCard`.
//
// The `isNote` predicate encodes the #860 "notes are notes regardless
// of anchor" semantics — a standalone annotation is always a note; a
// highlight is a note only when it carries a non-empty note string.
//
// Foundation-only — no SwiftUI — so the filter/count logic in
// `AnnotationStreamBuilder` is unit-testable without a render path.
//
// @coordinates-with: AnnotationStreamBuilder.swift, HighlightsSheet.swift,
//   HighlightAnnotationCard.swift, HighlightRecord.swift,
//   AnnotationRecord.swift

import Foundation

/// One item in `HighlightsSheet`'s unified card stream — either a
/// highlighted passage or a standalone note.
enum AnnotationStreamItem: Equatable, Identifiable, Sendable {
    /// A highlighted passage. Carries an optional note.
    case highlight(HighlightRecord)
    /// A standalone note — no anchored passage.
    case standalone(AnnotationRecord)

    /// Projects the underlying record's id (`highlightId` /
    /// `annotationId`) so SwiftUI `ForEach` has a stable identity.
    var id: UUID {
        switch self {
        case .highlight(let record):  return record.highlightId
        case .standalone(let record): return record.annotationId
        }
    }

    /// The record's creation timestamp — drives the chronological merge.
    var createdAt: Date {
        switch self {
        case .highlight(let record):  return record.createdAt
        case .standalone(let record): return record.createdAt
        }
    }

    /// True when this item is a "note" per the #860 semantics — a
    /// standalone annotation (always a note), OR a highlight carrying a
    /// non-empty note string. An empty-string note (`""`) is NOT a note
    /// — it matches the design's `h.note` truthiness check.
    var isNote: Bool {
        switch self {
        case .standalone:
            return true
        case .highlight(let record):
            return record.note?.isEmpty == false
        }
    }
}
