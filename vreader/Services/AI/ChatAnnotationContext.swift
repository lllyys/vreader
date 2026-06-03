// Purpose: Pure serializer turning the reader's own annotations into a context
// block the AI Chat tab folds alongside the book text (Feature #86 WI-2+). Kept
// out of the ViewModel so it stays unit-testable.
//
// "Notes" semantics match `AnnotationStreamBuilder`: standalone `AnnotationRecord`s
// PLUS highlights whose `note` is non-empty. A highlights-only seam would
// undercount (the app persists first-class standalone notes too).
//
// Key decisions:
// - Only toggled-on kinds are serialized; `allOff` → "" (nothing leaves the device).
// - Newest-first; budget-capped to a UTF-16 ceiling (CJK-safe: counts UTF-16 units).
// - Pure `enum` (no state) so the assembler + tests are deterministic.
//
// @coordinates-with: ChatSourceSelection.swift, ChatContextAssembler.swift,
//   ChatAnnotationCache.swift (WI-4), AnnotationStreamBuilder.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/design-notes/chat-ai-scope-sources.md`

import Foundation

enum ChatAnnotationContext {

    /// The section header each annotation kind serializes under — the assembler
    /// uses these to retain a kind's citation only if its section survived the
    /// budget clamp (Feature #86 WI-6 per-section retention).
    static let notesHeader = "Notes:"
    static let highlightsHeader = "Highlights:"
    static let bookmarksHeader = "Bookmarks:"

    /// A non-empty note: present and not whitespace-only.
    static func hasNote(_ note: String?) -> Bool {
        guard let note else { return false }
        return !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Per-kind counts for the sources popover.
    /// `notes` = standalone annotations + highlights with a non-empty note
    /// (matches `AnnotationStreamBuilder`).
    static func counts(
        annotations: [AnnotationRecord],
        highlights: [HighlightRecord],
        bookmarks: [BookmarkRecord]
    ) -> (notes: Int, highlights: Int, bookmarks: Int) {
        let annotatedHighlights = highlights.filter { hasNote($0.note) }.count
        return (
            notes: annotations.count + annotatedHighlights,
            highlights: highlights.count,
            bookmarks: bookmarks.count
        )
    }

    /// Serializes the selected annotation kinds into a `[Your notes & marks]`
    /// block, newest-first, budget-capped to `maxUTF16`. Returns "" when the
    /// selection is all-off or nothing matches.
    static func serialize(
        annotations: [AnnotationRecord],
        highlights: [HighlightRecord],
        bookmarks: [BookmarkRecord],
        selection: ChatSourceSelection,
        maxUTF16: Int
    ) -> String {
        guard !selection.allOff, maxUTF16 > 0 else { return "" }

        var sections: [String] = []

        if selection.notes {
            // Standalone notes + highlight-attached notes, newest-first. Each line
            // is prefixed with a stable locator label so the model (and WI-6's
            // citation row) can place where the reader marked it.
            let noteItems: [(Date, Locator, String)] =
                annotations.map { ($0.createdAt, $0.locator, $0.content) }
                + highlights.compactMap { h in
                    hasNote(h.note) ? (h.updatedAt, h.locator, h.note ?? "") : nil
                }
            let lines = noteItems
                .sorted { $0.0 > $1.0 }
                .map { line(label: locatorLabel($0.1), text: sanitize($0.2)) }
                .filter { !$0.isEmpty }
            if !lines.isEmpty {
                sections.append(notesHeader + "\n" + lines.joined(separator: "\n"))
            }
        }

        if selection.highlights {
            let lines = highlights
                .sorted { $0.createdAt > $1.createdAt }
                .map { line(label: locatorLabel($0.locator), text: sanitize($0.selectedText), quote: true) }
                .filter { !$0.isEmpty }
            if !lines.isEmpty {
                sections.append(highlightsHeader + "\n" + lines.joined(separator: "\n"))
            }
        }

        if selection.bookmarks {
            let lines = bookmarks
                .sorted { $0.createdAt > $1.createdAt }
                .map { line(label: locatorLabel($0.locator), text: sanitize($0.title ?? "Bookmark")) }
                .filter { !$0.isEmpty }
            if !lines.isEmpty {
                sections.append(bookmarksHeader + "\n" + lines.joined(separator: "\n"))
            }
        }

        guard !sections.isEmpty else { return "" }
        let body = "[Your notes & marks]\n" + sections.joined(separator: "\n\n")
        return UTF16Clamp.clamp(body, maxUTF16: maxUTF16)
    }

    /// A short, format-appropriate position label for a locator, or "" when none
    /// is derivable. PDF → "p.N" (1-based); TXT/MD → "@offset"; EPUB/AZW3 → the
    /// spine href basename; otherwise "".
    static func locatorLabel(_ locator: Locator) -> String {
        if let page = locator.page { return "p.\(page + 1)" }
        if let offset = locator.charOffsetUTF16 { return "@\(offset)" }
        if let href = locator.href {
            let base = href.split(separator: "/").last.map(String.init) ?? href
            let trimmed = base.split(separator: ".").first.map(String.init) ?? base
            return trimmed
        }
        return ""
    }

    // MARK: - Private

    /// Builds one bullet line: `- [label] text` (or `- [label] "text"` for a
    /// highlighted quote). The label is omitted when empty. Returns "" when the
    /// text is empty (so the caller filters it out).
    private static func line(label: String, text: String, quote: Bool = false) -> String {
        guard !text.isEmpty else { return "" }
        let shown = quote ? "\"\(text)\"" : text
        return label.isEmpty ? "- \(shown)" : "- [\(label)] \(shown)"
    }

    /// Collapses newlines/tabs so each annotation is one legible line.
    private static func sanitize(_ s: String) -> String {
        s.replacingOccurrences(of: "\r\n", with: " ")
         .replacingOccurrences(of: "\n", with: " ")
         .replacingOccurrences(of: "\t", with: " ")
         .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
