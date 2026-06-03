// Purpose: Per-book cache of the reader's own annotations for the AI Chat tab's
// sources feature (Feature #86 WI-4). Holds the fetched standalone notes /
// highlights / bookmarks + their counts, so the chat-context funnel can assemble
// the "[Your notes & marks]" block WITHOUT hitting SwiftData on every relocate.
//
// It loads once when the reader opens and refreshes ONLY on the single
// mutation-complete bus `.readerAnnotationsDidChange` (posted by PersistenceActor
// after a successful annotation save, WI-2) — never on a position change. This is
// the Gate-2 fix that keeps annotation I/O out of the relocate path.
//
// @coordinates-with: ChatAnnotationContext.swift, ReaderAICoordinator.swift,
//   AnnotationPersisting.swift, HighlightPersisting.swift, BookmarkPersisting.swift,
//   ReaderNotifications.swift (.readerAnnotationsDidChange)

import Foundation
import SwiftUI

/// A per-book cache of the reader's annotations for the Chat sources feature.
@MainActor
@Observable
final class ChatAnnotationCache {

    private(set) var annotations: [AnnotationRecord] = []
    private(set) var highlights: [HighlightRecord] = []
    private(set) var bookmarks: [BookmarkRecord] = []

    /// Per-kind counts for the sources popover (notes = standalone + annotated highlights).
    var counts: (notes: Int, highlights: Int, bookmarks: Int) {
        ChatAnnotationContext.counts(
            annotations: annotations, highlights: highlights, bookmarks: bookmarks
        )
    }

    /// Set by the coordinator: invoked after each (re)load so the chat context +
    /// the sources-chip counts re-assemble when an annotation mutation lands.
    var onChange: (() -> Void)?

    private let fingerprintKey: String
    private let annotationStore: any AnnotationPersisting
    private let highlightStore: any HighlightPersisting
    private let bookmarkStore: any BookmarkPersisting
    /// `nonisolated(unsafe)` so the nonisolated `deinit` can remove the observer
    /// (Swift 6 forbids a nonisolated deinit from touching a MainActor-isolated
    /// stored property). Set once in `init` (MainActor), read once in `deinit`
    /// after all references are gone — no concurrent access. `NotificationCenter`
    /// removal is itself thread-safe.
    nonisolated(unsafe) private var changeObserver: NSObjectProtocol?
    /// Monotonic load generation — guards against interleaved reloads (Gate-4
    /// High): rapid `.readerAnnotationsDidChange` posts spawn overlapping
    /// `load()` Tasks, and only the newest may publish state + fire `onChange`.
    private var loadGeneration = 0

    init(
        fingerprintKey: String,
        annotationStore: any AnnotationPersisting,
        highlightStore: any HighlightPersisting,
        bookmarkStore: any BookmarkPersisting
    ) {
        self.fingerprintKey = fingerprintKey
        self.annotationStore = annotationStore
        self.highlightStore = highlightStore
        self.bookmarkStore = bookmarkStore
        // Refresh on the mutation-complete bus ONLY (not on relocate).
        changeObserver = NotificationCenter.default.addObserver(
            forName: .readerAnnotationsDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.load() }
        }
    }

    deinit {
        if let changeObserver {
            NotificationCenter.default.removeObserver(changeObserver)
        }
    }

    /// Fetches the three annotation kinds for this book. Called once on open and
    /// on each `.readerAnnotationsDidChange`. A fetch failure leaves that kind
    /// empty (the AI context simply omits it — never blocks the chat).
    func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        // Fetch into locals across the awaits, THEN commit atomically — so an
        // older reload that finishes last can't leave a mixed/stale snapshot.
        let fetchedAnnotations = (try? await annotationStore.fetchAnnotations(forBookWithKey: fingerprintKey)) ?? []
        let fetchedHighlights = (try? await highlightStore.fetchHighlights(forBookWithKey: fingerprintKey)) ?? []
        let fetchedBookmarks = (try? await bookmarkStore.fetchBookmarks(forBookWithKey: fingerprintKey)) ?? []
        guard generation == loadGeneration else { return }   // a newer load superseded us
        annotations = fetchedAnnotations
        highlights = fetchedHighlights
        bookmarks = fetchedBookmarks
        onChange?()
    }

    /// The serialized `[Your notes & marks]` block for the given source selection,
    /// budget-capped. Empty when the selection is all-off or nothing matches.
    func annotationBlock(for selection: ChatSourceSelection, maxUTF16: Int) -> String {
        ChatAnnotationContext.serialize(
            annotations: annotations, highlights: highlights, bookmarks: bookmarks,
            selection: selection, maxUTF16: maxUTF16
        )
    }
}
